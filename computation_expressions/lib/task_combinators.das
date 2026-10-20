options gen2
module task_combinators public
require ./task_builder.das public
require daslib/rtti

struct TaskAllPolicy {_ce_marker:uint8}
struct TaskResultAllPolicy {_ce_marker:uint8}
struct TaskArrayTag {_ce_marker:uint8}
struct TaskArrayEventTag {_ce_marker:uint8}

// Resumable CE uses the same source grouping protocol as eager builders.
// The pair combinators consume owners and poll left-to-right cooperatively.
def ce_merge_sources(builder:tuple<kind:TaskContext;element:auto>;
    var left:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(CeTaskMergeLeft)>>;status:TaskStatus;value:CeTaskMergeLeft;error:string;polling:bool>;
    var right:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(CeTaskMergeRight)>>;status:TaskStatus;value:CeTaskMergeRight;error:string;polling:bool>) {
    return <- task_when_all(left,right)
}

// Match the whole payload, rather than a nested variant pattern: the 0.6.4
// compiler crashes on that pattern when a Result contains a grouped pair.
def ce_merge_sources(builder:tuple<kind:TaskResultContext;element:auto>;
    var left:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(CeTaskMergeLeft)>>;status:TaskStatus;value:CeTaskMergeLeft;error:string;polling:bool>;
    var right:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(CeTaskMergeRight)>>;status:TaskStatus;value:CeTaskMergeRight;error:string;polling:bool>) {
    return <- task_result_when_all(left,right)
}

// Owning array results use the same Task representation as any other payload.
def private task_array_store(var target:auto(Target)&; var child:auto) {
    static_if(typeinfo can_copy(target)) {target=task_value(child)}
    else {target <- child.value}
}

def task_when_all(var children:array<auto(C)>) {
    typedef ArrayValue=typedecl(children[0].value) -const -&
    static_assert(typeinfo ce_resumable_payload(default<ArrayValue>))
    for(i in range(length(children))) {if(ce_task_is_polling(children[i])) {panic("task_when_all array: cannot move a task being polled")}}
    var values:array<ArrayValue>
    values.resize(length(children))
    for(i in range(length(children))) {
        if(task_status(children[i])==TaskStatus.Succeeded) {task_array_store(values[i],children[i])}
    }
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:array<ArrayValue>>> capture(<-children,<-values) {
        while(true) {
            var complete=true
            for(i in range(length(children))) {
                if(task_status(children[i])==TaskStatus.Succeeded) {continue}
                let status=task_poll(children[i])
                if(!task_check_child(status,task_error(children[i]))) {
                    yield <- task_pending(type<array<ArrayValue>>)
                    return false
                }
                if(status==TaskStatus.Succeeded) {task_array_store(values[i],children[i])}
                else {complete=false}
            }
            if(complete) {yield <- task_ready_move(values);return false}
            yield <- task_pending(type<array<ArrayValue>>)
        }
        return false
    } finally {ce_sequence_finalize($ {task_release_array(children);delete values})}
    return <- task_create(events)
}

def private task_release_array(var children:array<auto>) {
    for(child in children) {
        let error=task_release_child(child)
        if(!empty(error)) {ce_task_cleanup_error(error)}
    }
    delete children
}

def private task_pair_shape(policy:TaskAllPolicy; left:auto(A);right:auto(B)) {
    return <- (first <- default<A -const -&>,second <- default<B -const -&>)
}
def private task_pair_shape(policy:TaskResultAllPolicy;
    left:$Result<auto(A);string>;right:$Result<auto(B);string>) {
    var pair <- (first <- default<A -const -&>,second <- default<B -const -&>)
    return <- move_ok(pair)
}

def private task_pair_value(policy:TaskAllPolicy; var left:auto; var right:auto) {
    return <- (first <- left,second <- right)
}
def private task_pair_value(policy:TaskResultAllPolicy;
    var left:$Result<auto(A);string>; var right:$Result<auto(B);string>) {
    var pair <- (first <- left as ok,second <- right as ok)
    return <- move_ok(pair)
}

def private task_pair_stops(policy:TaskAllPolicy; value:auto) {return false}
def private task_pair_stops(policy:TaskResultAllPolicy; value:$Result<auto(T);string>) {return value is err}
def private task_pair_error(policy:TaskAllPolicy; value:auto; unused:type<auto(T)>) {var result:T -const -&;return <- result}
def private task_pair_error(policy:TaskResultAllPolicy; value:$Result<auto(T);string>; unused:type<auto(R)>) {
    var result:R -const -& = variant type<R -const -&>(err=value as err)
    return <- result
}

// Both arguments are consuming owners. Aliases must be rejected before moving.
def private task_check_distinct(var left:auto; var right:auto) {
    unsafe {
        if(reinterpret<void?>(addr(left))==reinterpret<void?>(addr(right))) {
            panic("task composition: the same owner cannot be passed twice")
        }
    }
}
def private task_check_child(status:TaskStatus; error:string) : bool {
    if(status==TaskStatus.Failed) {panic(error)}
    if(status==TaskStatus.Cancelled || ce_task_cancellation_requested()) {ce_task_cancelled();return false}
    return true
}
def private task_release_child(var task:auto) : string {
    let cancelled=task_cancel(task)
    var error=""
    if(cancelled && task_status(task)==TaskStatus.Failed) {error=task_error(task)}
    delete task
    return error
}
def private task_release_pair(var left:auto; var right:auto) {
    let first=task_release_child(left)
    let second=task_release_child(right)
    if(!empty(first)) {ce_task_cleanup_error(first)}
    if(!empty(second)) {ce_task_cleanup_error(second)}
}

def private task_pair_pending(policy:auto; left:auto; right:auto) {
    return <- task_pending(type<typedecl(task_pair_shape(policy,left,right)) -const -&>)
}
def private task_pair(var left:auto(L); var right:auto(R); policy:auto(P)) {
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:typedecl(task_pair_shape(policy,left.value,right.value)) -const -&>> capture(<-left,<-right) {
        while(true) {
            let first=task_poll(left)
            if(!task_check_child(first,task_error(left))) {yield <- task_pair_pending(policy,left.value,right.value);return false}
            if(first==TaskStatus.Succeeded && task_pair_stops(policy,left.value)) {
                var error <- task_pair_error(policy,left.value,type<typedecl(task_pair_shape(policy,left.value,right.value)) -const -&>);yield <- task_ready_move(error)
                return false
            }
            let second=task_poll(right)
            if(!task_check_child(second,task_error(right))) {yield <- task_pair_pending(policy,left.value,right.value);return false}
            if(second==TaskStatus.Succeeded && task_pair_stops(policy,right.value)) {
                var error <- task_pair_error(policy,right.value,type<typedecl(task_pair_shape(policy,left.value,right.value)) -const -&>);yield <- task_ready_move(error)
                return false
            }
            if(first==TaskStatus.Succeeded && second==TaskStatus.Succeeded) {
                var value <- task_pair_value(policy,left.value,right.value);yield <- task_ready_move(value)
                return false
            }
            yield <- task_pair_pending(policy,left.value,right.value)
        }
        return false
    } finally {ce_sequence_finalize($ {task_release_pair(left,right)})}
    return <- task_create(events)
}

// At most one poll per active child per parent poll, in left-to-right order.
def task_when_all(var left:auto(L); var right:auto(R)) {
    task_check_distinct(left,right)
    var inscope first <- ce_task_source(left)
    var inscope second <- ce_task_source(right)
    return <- task_pair(first,second,TaskAllPolicy())
}
def task_result_when_all(var left:auto(L); var right:auto(R)) {
    task_check_distinct(left,right)
    var inscope first <- ce_task_source(left)
    var inscope second <- ce_task_source(right)
    var inscope a <- ce_task_result_source(first)
    var inscope b <- ce_task_result_source(second)
    return <- task_pair(a,b,TaskResultAllPolicy())
}

def private ce_task_result_source(var source:auto) {return <- source}
def private ce_task_result_source(var source:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:CeUnit>>;status:TaskStatus;value:CeUnit;error:string;polling:bool>) {
    var stream <- ce_await_source(TaskBuilder(type<CeUnit>),source)
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:$Result<CeUnit;string>>> capture(<-stream) {
        for(event in stream) {
            if(event.ready) {yield task_ready(result_ok(CeUnit()));return false}
            yield task_pending(type<$Result<CeUnit;string>>)
        }
        return false
    } finally {ce_sequence_finalize($ {sequence_close(stream)})}
    return <- task_create(events)
}

def task_result_when_all(var children:array<auto(C)>) {
    for(i in range(length(children))) {if(ce_task_is_polling(children[i])) {panic("task_result_when_all: cannot move a task being polled")}}
    var inscope sources:array<typedecl(ce_task_result_source(ce_task_source(children[0])))>
    for(i in range(length(children))) {
        var task <- ce_task_source(children[i])
        sources |> emplace(ce_task_result_source(task))
    }
    delete children
    return <- ce_task_result_array(sources)
}

def private ce_task_result_array(var children:array<auto(C)>) {
    typedef ResultItem=typedecl(children[0].value as ok) -const -&
    var values:array<ResultItem>
    var done:array<bool>
    values.resize(length(children));done.resize(length(children))
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:$Result<array<ResultItem>;string>>> capture(<-children,<-values,<-done) {
        while(true) {
            var complete=true
            for(i in range(length(children))) {
                if(done[i]) {continue}
                let status=task_poll(children[i])
                if(!task_check_child(status,task_error(children[i]))) {
                    yield <- task_pending(type<$Result<array<ResultItem>;string>>);return false
                }
                if(status==TaskStatus.Succeeded) {
                    if(children[i].value is err) {
                        var error <- move_error(children[i].value as err,type<array<ResultItem>>)
                        yield <- task_ready_move(error);return false
                    }
                    values[i] <- children[i].value as ok
                    done[i]=true
                } else {complete=false}
            }
            if(complete) {var result <- move_ok(values);yield <- task_ready_move(result);return false}
            yield <- task_pending(type<$Result<array<ResultItem>;string>>)
        }
        return false
    } finally {ce_sequence_finalize($ {task_release_array(children);delete values;delete done})}
    return <- task_create(events)
}

def task_when_all(var children:array<tuple<tag:TaskSharedTag;owner:iterator<auto(ShareState)?>>>) {
    var inscope sources:array<typedecl(ce_task_source(children[0]))>
    for(i in range(length(children))) {sources |> emplace(ce_task_source(children[i]))}
    delete children
    return <- task_when_all(sources)
}

def task_result_race(var left:auto;var right:auto) {
    task_check_distinct(left,right)
    var inscope first <- ce_task_source(left)
    var inscope second <- ce_task_source(right)
    var inscope a <- ce_task_result_source(first)
    var inscope b <- ce_task_result_source(second)
    typedef RaceValue=typedecl(a.value as ok) -const -&
    typedef RacePayload=tuple<index:int;value:RaceValue>
    var raced <- task_race(a,b)
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:$Result<RacePayload;string>>> capture(<-raced) {
        while(true) {
            let status=task_poll(raced)
            if(!task_check_child(status,task_error(raced))) {
                yield <- task_pending(type<$Result<RacePayload;string>>);return false
            }
            if(status==TaskStatus.Succeeded) {
                if(raced.value.value is err) {
                    var error <- move_error(raced.value.value as err,type<RacePayload>)
                    yield <- task_ready_move(error);return false
                }
                var pair <- (index=raced.value.index,value <- raced.value.value as ok)
                var result <- move_ok(pair)
                yield <- task_ready_move(result);return false
            }
            yield <- task_pending(type<$Result<RacePayload;string>>)
        }
        return false
    } finally {ce_sequence_finalize($ {let error=task_release_child(raced);if(!empty(error)){ce_task_cleanup_error(error)}})}
    return <- task_create(events)
}

// First terminal child wins. A tie is won by the left child without polling right.
// Native faults fail the parent; cancelled children cancel it. Losers are closed.
def private task_race_impl(var left,right:auto(T)) {
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:tuple<index:int;value:typedecl(left.value) -const -&>>> capture(<-left,<-right) {
        while(true) {
            let first=task_poll(left)
            if(!task_check_child(first,task_error(left))) {
                yield <- task_pending(type<tuple<index:int;value:typedecl(left.value) -const -&>>)
                return false
            }
            if(first==TaskStatus.Succeeded) {var value <- (index=0,value <- left.value);yield <- task_ready_move(value);return false}
            let second=task_poll(right)
            if(!task_check_child(second,task_error(right))) {
                yield <- task_pending(type<tuple<index:int;value:typedecl(left.value) -const -&>>)
                return false
            }
            if(second==TaskStatus.Succeeded) {var value <- (index=1,value <- right.value);yield <- task_ready_move(value);return false}
            yield <- task_pending(type<tuple<index:int;value:typedecl(left.value) -const -&>>)
        }
        return false
    } finally {ce_sequence_finalize($ {task_release_pair(left,right)})}
    return <- task_create(events)
}
def task_race(var left,right:auto(T)) {
    task_check_distinct(left,right)
    var inscope first <- ce_task_source(left)
    var inscope second <- ce_task_source(right)
    return <- task_race_impl(first,second)
}
