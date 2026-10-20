options gen2
module task_runtime public
require ./task_scheduler.das public

struct TaskRuntimeTag {_ce_marker:uint8}
struct TaskTicketTag {_ce_marker:uint8}

def task_runtime(config:TaskSchedulerConfig) {
    return <- (kind=TaskRuntimeTag(),scheduler <- task_scheduler(type<CeUnit>,config))
}
def task_runtime() {return <- task_runtime(TaskSchedulerConfig())}

def private ce_task_erased(var handle:auto) {
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:CeUnit>> capture(<-handle) {
        while(true) {
            let status=task_poll(handle)
            if(status==TaskStatus.Failed) {panic(task_error(handle))}
            if(status==TaskStatus.Cancelled) {ce_task_cancelled();yield task_pending(type<CeUnit>);return false}
            if(status==TaskStatus.Succeeded) {yield task_ready(CeUnit());return false}
            yield task_pending(type<CeUnit>)
        }
        return false
    } finally {ce_sequence_finalize($ {
        let cancelled=task_cancel(handle)
        if(cancelled && task_status(handle)==TaskStatus.Failed) {ce_task_cleanup_error(task_error(handle))}
        delete handle
    })}
    return <- task_create(events)
}
def private ce_runtime_spawn(var runtime:auto;var source:auto;timed:bool;timeout:TaskTimeout;name:string) {
    var inscope owned <- ce_task_source(source)
    var inscope handle <- task_share(owned)
    var copy <- task_shared_clone(handle)
    var inscope erased <- ce_task_erased(copy)
    var id:TaskId
    if(timed) {id=task_spawn_named(runtime.scheduler,name,erased,timeout)}
    else {id=task_spawn_named(runtime.scheduler,name,erased)}
    return <- (tag=TaskTicketTag(),id=id,handle <- handle)
}
def task_spawn(var runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>;var source:auto) {
    return <- ce_runtime_spawn(runtime,source,false,TaskTimeout(),"")
}
def task_spawn(var runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>;var source:auto;timeout:TaskTimeout) {
    return <- ce_runtime_spawn(runtime,source,true,timeout,"")
}
def task_spawn_named(var runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>;name:string;var source:auto) {
    return <- ce_runtime_spawn(runtime,source,false,TaskTimeout(),name)
}
def task_spawn_named(var runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>;name:string;var source:auto;timeout:TaskTimeout) {
    return <- ce_runtime_spawn(runtime,source,true,timeout,name)
}
def task_name(runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>;ticket:tuple<tag:TaskTicketTag;id:TaskId;handle:auto>) {return task_name(runtime.scheduler,ticket.id)}
def task_next_deadline(runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>) {return task_next_deadline(runtime.scheduler)}
def task_dump(runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>) {return <- task_dump(runtime.scheduler)}
def task_dump_text(runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>) {return task_dump_text(runtime.scheduler)}
def task_stalled(runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>;older_than_ms:int64) {return <- task_stalled(runtime.scheduler,older_than_ms)}
def task_stalled(runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>;older_than_ms:int) {return <- task_stalled(runtime.scheduler,int64(older_than_ms))}
def task_tick(var runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>;now_ms:int64) {return task_tick(runtime.scheduler,now_ms)}
def task_tick(var runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>;now_ms:int) {return task_tick(runtime.scheduler,now_ms)}
def task_status(ticket:tuple<tag:TaskTicketTag;id:TaskId;handle:auto>) {return task_status(ticket.handle)}
def task_value(ticket:tuple<tag:TaskTicketTag;id:TaskId;handle:auto>) {
    static_if(typeinfo can_copy(type<typedecl(task_value(ticket.handle))>)) {return task_value(ticket.handle)}
    else {return <- task_value(ticket.handle)}
}
def task_error(ticket:tuple<tag:TaskTicketTag;id:TaskId;handle:auto>) {return task_error(ticket.handle)}
def task_cancel(var runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>;ticket:tuple<tag:TaskTicketTag;id:TaskId;handle:auto>) {return task_cancel(runtime.scheduler,ticket.id)}
def task_timed_out(runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>;ticket:tuple<tag:TaskTicketTag;id:TaskId;handle:auto>) {return task_timed_out(runtime.scheduler,ticket.id)}
def task_forget(var runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>;ticket:tuple<tag:TaskTicketTag;id:TaskId;handle:auto>) {return task_forget(runtime.scheduler,ticket.id)}
def task_prune(var runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>) {return task_prune(runtime.scheduler)}
def task_active_count(runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>) {return task_active_count(runtime.scheduler)}
def task_count(runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>) {return task_count(runtime.scheduler)}
def task_scheduler_close(var runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>) {task_scheduler_close(runtime.scheduler)}
def task_configure(var runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>;config:TaskSchedulerConfig) {task_configure(runtime.scheduler,config)}
def finalize(var runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>) {delete runtime.scheduler}

// Awaiting a ticket observes the scheduler; it never polls its source twice.
def task_await(ticket:tuple<tag:TaskTicketTag;id:TaskId;handle:auto>) {
    var handle <- task_shared_clone(ticket.handle)
    typedef Value=typedecl(task_value(handle)) -const -&
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:Value>> capture(<-handle) {
        while(true) {
            let status=task_status(handle)
            if(status==TaskStatus.Failed) {panic(task_error(handle))}
            if(status==TaskStatus.Cancelled) {ce_task_cancelled();yield <- task_pending(type<Value>);return false}
            if(status==TaskStatus.Succeeded) {
                var value <- task_value(handle)
                yield <- task_ready_move(value);return false
            }
            yield <- task_pending(type<Value>)
        }
        return false
    } finally {ce_sequence_finalize($ {delete handle})}
    return <- task_create(events)
}

def task_take(var ticket:tuple<tag:TaskTicketTag;id:TaskId;handle:auto>) {return <- task_take(ticket.handle)}

def task_valid(runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>;ticket:tuple<tag:TaskTicketTag;id:TaskId;handle:auto>) {return task_valid(runtime.scheduler,ticket.id)}
def task_slot_count(runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>) {return task_slot_count(runtime.scheduler)}
def task_scheduler_config(runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>) {return task_scheduler_config(runtime.scheduler)}
def task_scheduler_time(runtime:tuple<kind:TaskRuntimeTag;scheduler:auto>) {return task_scheduler_time(runtime.scheduler)}
