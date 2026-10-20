options gen2
module task_parallel public
require ./task_channel.das public
require ./task_delay.das public

struct TaskSemaphoreTag {_ce_marker:uint8}

def task_semaphore(permits:int) {
    var inscope channel <- task_channel(type<CeUnit>,permits)
    for(i in range(permits)) {verify(task_channel_try_send(channel,CeUnit()))}
    return <- (tag=TaskSemaphoreTag(),channel <- channel)
}
def task_semaphore_close(semaphore:tuple<tag:TaskSemaphoreTag;channel:auto>) {task_channel_fail(semaphore.channel,"semaphore is closed")}
// Explicit acquire/release is available; task_with_semaphore scopes a permit.
def task_semaphore_release(semaphore:tuple<tag:TaskSemaphoreTag;channel:auto>) {
    if(!task_channel_try_send(semaphore.channel,CeUnit())) {panic("task semaphore: closed or released too often")}
}
def task_semaphore_acquire(semaphore:tuple<tag:TaskSemaphoreTag;channel:auto>) {
    var waiting <- task_channel_receive(semaphore.channel)
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:$Result<CeUnit;string>>> capture(<-waiting) {
        while(true) {
            let status=task_poll(waiting)
            if(status==TaskStatus.Failed) {panic(task_error(waiting))}
            if(status==TaskStatus.Cancelled) {ce_task_cancelled();yield task_pending(type<$Result<CeUnit;string>>);return false}
            if(status==TaskStatus.Succeeded) {
                if(waiting.value is err || (waiting.value as ok) is none) {yield task_ready(result_error("semaphore is closed",type<CeUnit>));return false}
                yield task_ready(result_ok(CeUnit()));return false
            }
            yield task_pending(type<$Result<CeUnit;string>>)
        }
        return false
    } finally {ce_sequence_finalize($ {ce_task_parallel_close(waiting)})}
    return <- task_create(events)
}
def task_with_semaphore(semaphore:tuple<tag:TaskSemaphoreTag;channel:auto>;var factory:lambda<():auto(Child)>) {
    var lease <- task_channel_clone(semaphore.channel)
    var waiting <- task_channel_receive(lease)
    var child:Child -const -&
    typedef Value=typedecl(child.value) -const -&
    var claimed=false
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:Value>> capture(<-lease,<-waiting,<-child,<-factory,copy(claimed)) {
        while(task_poll(waiting)!=TaskStatus.Succeeded) {
            if(waiting.status==TaskStatus.Failed) {panic(task_error(waiting))}
            if(waiting.status==TaskStatus.Cancelled) {ce_task_cancelled();yield <- task_pending(type<Value>);return false}
            yield <- task_pending(type<Value>)
        }
        if(waiting.value is err || (waiting.value as ok) is none) {panic("semaphore is closed")}
        claimed=true
        child <- invoke(factory)
        while(true) {
            let status=task_poll(child)
            if(status==TaskStatus.Failed) {panic(task_error(child))}
            if(status==TaskStatus.Cancelled) {ce_task_cancelled();yield <- task_pending(type<Value>);return false}
            if(status==TaskStatus.Succeeded) {yield <- task_ready_move(child.value);return false}
            yield <- task_pending(type<Value>)
        }
        return false
    } finally {ce_sequence_finalize($ {
        ce_task_parallel_close(child);ce_task_parallel_close(waiting)
        if(claimed) {task_channel_try_send(lease,CeUnit())}
        delete lease;unsafe {delete factory}
    })}
    return <- task_create(events)
}

// Retry only explicit Result.err; cancellation and native failures propagate.
def task_retry(var factory:lambda<(attempt:int):auto(Child)>;max_attempts:int;delay_ms:int64=0l) {
    if(max_attempts<=0 || delay_ms<0l) {panic("task_retry: attempts must be positive and delay non-negative")}
    typedef Outcome=typedecl(invoke(factory,1).value) -const -&
    var child:Child -const -&
    var pause:typedecl(task_delay_ms(delay_ms))
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:Outcome>> capture(<-factory,<-child,<-pause,copy(max_attempts),copy(delay_ms)) {
        for(index in range(max_attempts)) {
            let attempt=index+1
            child <- invoke(factory,attempt)
            while(true) {
                let status=task_poll(child)
                if(status==TaskStatus.Failed) {panic(task_error(child))}
                if(status==TaskStatus.Cancelled) {ce_task_cancelled();yield <- task_pending(type<Outcome>);return false}
                if(status==TaskStatus.Succeeded) {break}
                yield <- task_pending(type<Outcome>)
            }
            if(child.value is ok || attempt==max_attempts) {yield <- task_ready_move(child.value);return false}
            delete child
            if(delay_ms>0l) {
                pause <- task_delay_ms(delay_ms)
                while(true) {
                    let status=task_poll(pause)
                    if(status==TaskStatus.Failed) {panic(task_error(pause))}
                    if(status==TaskStatus.Cancelled) {ce_task_cancelled();yield <- task_pending(type<Outcome>);return false}
                    if(status==TaskStatus.Succeeded) {break}
                    yield <- task_pending(type<Outcome>)
                }
                delete pause
            } else {yield <- task_pending(type<Outcome>)}
        }
        return false
    } finally {ce_sequence_finalize($ {ce_task_parallel_close(child);ce_task_parallel_close(pause);unsafe {delete factory}})}
    return <- task_create(events)
}

def task_first_success(var children:array<auto(Child)>) {
    typedef Outcome=typedecl(children[0].value) -const -&
    typedef Item=typedecl(children[0].value as ok) -const -&
    var done:array<bool>;done.resize(length(children))
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:Outcome>> capture(<-children,<-done) {
        var remaining=length(children)
        var last_error="task_first_success: no candidates"
        while(remaining>0) {
            for(i in range(length(children))) {
                if(done[i]) {continue}
                let status=task_poll(children[i])
                if(status==TaskStatus.Failed) {panic(task_error(children[i]))}
                if(status==TaskStatus.Cancelled) {ce_task_cancelled();yield <- task_pending(type<Outcome>);return false}
                if(status==TaskStatus.Succeeded) {
                    if(children[i].value is ok) {yield <- task_ready_move(children[i].value);return false}
                    last_error=children[i].value as err
                    done[i]=true;remaining--;delete children[i]
                }
            }
            if(remaining>0) {yield <- task_pending(type<Outcome>)}
        }
        var error <- move_error(last_error,type<Item>);yield <- task_ready_move(error)
        return false
    } finally {ce_sequence_finalize($ {ce_task_parallel_release(children);delete done})}
    return <- task_create(events)
}

def private ce_task_parallel_release(var children:array<auto>) {
    for(child in children) {ce_task_parallel_close(child)}
    delete children
}

// Factories are cold: queued inputs do not create a Task until a slot is free.
def task_when_all_limited(var inputs:array<auto(Input)>;limit:int;var factory:lambda<(input:Input):auto(Child)>) {
    if(limit<=0) {panic("task_when_all_limited: limit must be positive")}
    typedef Item=typedecl(invoke(factory,inputs[0]).value) -const -&
    var values:array<Item>;values.resize(length(inputs))
    var children:array<Child -const -&>;children.resize(length(inputs))
    var states:array<int>;states.resize(length(inputs))
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:array<Item>>> capture(<-inputs,<-factory,<-children,<-states,<-values,copy(limit)) {
        var next_index=0;var active=0;var completed=0
        while(completed<length(inputs)) {
            while(active<limit && next_index<length(inputs)) {
                children[next_index] <- invoke(factory,inputs[next_index]);states[next_index]=1
                active++;next_index++
            }
            for(i in range(next_index)) {
                if(states[i]!=1) {continue}
                let status=task_poll(children[i])
                if(status==TaskStatus.Failed) {panic(task_error(children[i]))}
                if(status==TaskStatus.Cancelled) {ce_task_cancelled();yield <- task_pending(type<array<Item>>);return false}
                if(status==TaskStatus.Succeeded) {
                    values[i] <- children[i].value
                    delete children[i];states[i]=2;active--;completed++
                }
            }
            if(completed<length(inputs)) {yield <- task_pending(type<array<Item>>)}
        }
        yield <- task_ready_move(values)
        return false
    } finally {ce_sequence_finalize($ {ce_task_parallel_release(children);delete inputs;delete states;delete values;unsafe {delete factory}})}
    return <- task_create(events)
}

// Factories are cold: queued inputs do not create a Task until a slot is free.
def task_result_when_all_limited(var inputs:array<auto(Input)>;limit:int;var factory:lambda<(input:Input):auto(Child)>) {
    if(limit<=0) {panic("task_result_when_all_limited: limit must be positive")}
    typedef Item=typedecl(invoke(factory,inputs[0]).value as ok) -const -&
    var values:array<Item>;values.resize(length(inputs))
    var children:array<Child -const -&>;children.resize(length(inputs))
    var states:array<int>;states.resize(length(inputs))
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:$Result<array<Item>;string>>> capture(<-inputs,<-factory,<-children,<-states,<-values,copy(limit)) {
        var next_index=0;var active=0;var completed=0
        while(completed<length(inputs)) {
            while(active<limit && next_index<length(inputs)) {
                children[next_index] <- invoke(factory,inputs[next_index]);states[next_index]=1
                active++;next_index++
            }
            for(i in range(next_index)) {
                if(states[i]!=1) {continue}
                let status=task_poll(children[i])
                if(status==TaskStatus.Failed) {panic(task_error(children[i]))}
                if(status==TaskStatus.Cancelled) {ce_task_cancelled();yield <- task_pending(type<$Result<array<Item>;string>>);return false}
                if(status==TaskStatus.Succeeded) {
                    if(children[i].value is err) {
                        var error <- move_error(children[i].value as err,type<array<Item>>)
                        yield <- task_ready_move(error);return false
                    }
                    values[i] <- children[i].value as ok
                    delete children[i];states[i]=2;active--;completed++
                }
            }
            if(completed<length(inputs)) {yield <- task_pending(type<$Result<array<Item>;string>>)}
        }
        var result <- move_ok(values);yield <- task_ready_move(result)
        return false
    } finally {ce_sequence_finalize($ {ce_task_parallel_release(children);delete inputs;delete states;delete values;unsafe {delete factory}})}
    return <- task_create(events)
}

def private ce_task_parallel_close(var child:auto) {
    let cancelled=task_cancel(child)
    if(cancelled && task_status(child)==TaskStatus.Failed) {ce_task_cleanup_error(task_error(child))}
    delete child
}
