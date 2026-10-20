options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require ../lib/task_events.das
require daslib/rtti
require daslib/strings_boost
var applied=0

def confirm(events:auto) {
    var wait <- task_wait_event(events)
    unsafe {return <- computation(TaskResultBuilder(type<string>)) {
        let action=wait |> bind
        applied++
        return "action={action}"
    }}
}
def balanced() {
    let s=task_event_stats()
    verify(s.sources==0 && s.waits==0 && s.subscriptions==0 && s.subscribed==s.unsubscribed)
}
def success_checks() {
    var inscope source <- task_event_source(type<string>)
    var inscope scheduler <- task_scheduler(type<$Result<string;string>>)
    let before=applied
    verify(task_event_emit(source,"before subscribing")==0)
    let a=task_spawn(scheduler,confirm(source))
    let b=task_spawn(scheduler,confirm(source))
    verify(task_event_subscriber_count(source)==0)
    verify(task_tick(scheduler,0)==2 && task_event_subscriber_count(source)==2)
    verify(task_event_emit(source,"confirm")==2)
    verify(task_event_emit(source,"ignored")==0 && applied==before)
    verify(task_tick(scheduler,1)==0 && applied==before+2)
    for(id in fixed_array(a,b)) {
        let value=task_value(scheduler,id)
        verify(value is ok && value as ok=="action=confirm")
    }
    verify(task_event_subscriber_count(source)==0)
    let c=task_spawn(scheduler,confirm(source))
    verify(task_tick(scheduler,2)==1)
    verify(task_event_emit(source,"next")==1 && task_tick(scheduler,3)==0)
    verify(task_value(scheduler,c) as ok=="action=next")
}
def cancellation_checks() {
    var inscope source <- task_event_source(type<string>)
    var inscope token <- cancellation_token()
    var inscope scheduler <- task_scheduler(type<$Result<string;string>>)
    let before=applied
    let a=task_spawn(scheduler,task_with_cancellation(confirm(source),token))
    let b=task_spawn(scheduler,task_with_cancellation(confirm(source),token))
    verify(task_tick(scheduler,0)==2 && task_event_subscriber_count(source)==2)
    cancellation_cancel(token)
    verify(task_tick(scheduler,1)==0)
    verify(task_status(scheduler,a)==TaskStatus.Cancelled && task_status(scheduler,b)==TaskStatus.Cancelled)
    verify(task_event_subscriber_count(source)==0 && applied==before)
    verify(task_event_emit(source,"late")==0)
    var inscope unpolled <- task_wait_event(source)
    verify(task_cancel(unpolled) && task_event_subscriber_count(source)==0)
}
def timeout_checks() {
    var inscope source <- task_event_source(type<string>)
    var inscope scheduler <- task_scheduler(type<$Result<string;string>>)
    let before=applied
    let a=task_spawn(scheduler,confirm(source),TaskTimeout(after_ms=5))
    verify(task_tick(scheduler,100)==1 && task_event_subscriber_count(source)==1)
    verify(task_tick(scheduler,104)==1)
    verify(task_tick(scheduler,105)==0 && task_status(scheduler,a)==TaskStatus.Cancelled)
    verify(task_timed_out(scheduler,a) && task_event_subscriber_count(source)==0 && applied==before)
    verify(task_event_emit(source,"late")==0)
}
def composition_checks() {
    unsafe {
        var inscope events <- task_event_source(type<string>)
        {
            var left <- task_wait_event(events)
            var right <- task_wait_event(events)
            var group <- computation(TaskResultBuilder(type<string>)) {
                let pair=left |> and_bind(right) |> bind
                verify(task_event_stats().subscriptions==0)
                return "{pair.first}/{pair.second}"
            }
            var inscope owned <- group
            verify(task_poll(owned)==TaskStatus.Waiting && task_event_subscriber_count(events)==2)
            verify(task_event_emit(events,"together")==2)
            verify(task_poll(owned)==TaskStatus.Succeeded && task_value(owned) as ok=="together/together")
        }
        {
            var inscope first <- task_wait_event(events)
            var inscope second <- task_wait_event(events)
            verify(task_poll(first)==TaskStatus.Waiting && task_poll(second)==TaskStatus.Waiting)
            verify(task_cancel(first) && task_event_subscriber_count(events)==1)
            verify(task_event_emit(events,"survivor")==1)
            verify(task_poll(second)==TaskStatus.Succeeded && task_value(second) as ok=="survivor")
        }
        {
            var wait <- task_wait_event(events)
            var inscope failed <- computation(TaskResultBuilder(type<string>)) {
                let value=wait |> bind
                verify(task_event_stats().subscriptions==0)
                panic("event handler failed")
                return value
            }
            verify(task_poll(failed)==TaskStatus.Waiting)
            verify(task_event_emit(events,"fault")==1)
            verify(task_poll(failed)==TaskStatus.Failed && starts_with(task_error(failed),"event handler failed"))
            verify(task_event_subscriber_count(events)==0)
        }
        {
            var inscope scheduler <- task_scheduler(type<$Result<string;string>>)
            let a=task_spawn(scheduler,confirm(events))
            let b=task_spawn(scheduler,confirm(events))
            verify(task_tick(scheduler,0)==2)
            task_scheduler_close(scheduler)
            verify(task_event_subscriber_count(events)==0)
        }
        {
            var inscope otherEvents <- task_event_source(type<string>)
            var left <- task_wait_event(events)
            var right <- task_wait_event(otherEvents)
            var inscope winner <- task_race(left,right)
            verify(task_poll(winner)==TaskStatus.Waiting)
            verify(task_event_subscriber_count(events)==1 && task_event_subscriber_count(otherEvents)==1)
            verify(task_event_emit(otherEvents,"winner")==1)
            verify(task_poll(winner)==TaskStatus.Succeeded)
            let result=task_value(winner)
            verify(result.index==1 && result.value as ok=="winner")
            verify(task_event_subscriber_count(events)==0 && task_event_subscriber_count(otherEvents)==0)
        }
        var unstarted <- confirm(events)
        verify(task_cancel(unstarted))
        delete unstarted
        verify(task_event_subscriber_count(events)==0)
    }
}

def value_checks() {
    unsafe {
        var inscope numbers <- task_event_source(type<int>)
        var inscope value <- task_wait_event(numbers)
        verify(task_poll(value)==TaskStatus.Waiting)
        verify(task_event_emit(numbers,42)==1 && task_poll(value)==TaskStatus.Succeeded)
        verify(task_value(value) as ok==42)
        {
            var inscope text <- task_event_source(type<string>)
            var inscope copied <- task_wait_event(text)
            verify(task_poll(copied)==TaskStatus.Waiting)
            var bytes <- [uint8('o'),uint8('k'),uint8(0)]
            let borrowed=reinterpret<string#>(addr(bytes[0]))
            verify(task_event_emit(text,borrowed)==1)
            bytes[0]=uint8('x')
            delete bytes
            verify(task_poll(copied)==TaskStatus.Succeeded && task_value(copied) as ok=="ok")
        }
        var inscope clicks <- task_event_source(type<CeUnit>)
        var inscope unit <- task_wait_event(clicks)
        verify(task_poll(unit)==TaskStatus.Waiting)
        verify(task_event_emit(clicks,CeUnit())==1 && task_poll(unit)==TaskStatus.Succeeded)
        var inscope closed <- task_event_source(type<string>)
        verify(task_event_close(closed))
        var pending <- task_wait_event(closed)
        var inscope explicitResult <- computation(TaskBuilder(type<bool>)) {
            let result=pending |> bind
            return result is err
        }
        verify(task_poll(explicitResult)==TaskStatus.Succeeded && task_value(explicitResult))
    }
}

def lifetime_checks() {
    {
        var source <- task_event_source(type<string>)
        var inscope pending <- task_wait_event(source)
        verify(task_poll(pending)==TaskStatus.Waiting)
        delete source
        verify(task_poll(pending)==TaskStatus.Succeeded && task_value(pending) is err)
    }
    balanced()
    {
        var source <- task_event_source(type<string>)
        var inscope unpolled <- task_wait_event(source)
        delete source
        verify(task_poll(unpolled)==TaskStatus.Succeeded && task_value(unpolled) is err)
    }
    balanced()
    {
        var inscope source <- task_event_source(type<string>)
        var pending <- task_wait_event(source)
        verify(task_poll(pending)==TaskStatus.Waiting && task_event_subscriber_count(source)==1)
        delete pending
        verify(task_event_subscriber_count(source)==0)
        var inscope moved <- source
        var inscope next <- task_wait_event(moved)
        verify(task_poll(next)==TaskStatus.Waiting)
        verify(task_event_emit(moved,"saved")==1)
        verify(task_event_close(moved) && !task_event_close(moved))
        verify(task_event_emit(moved,"ignored")==0)
        verify(task_poll(next)==TaskStatus.Succeeded && task_value(next) as ok=="saved")
        var inscope closed <- task_wait_event(moved)
        verify(task_poll(closed)==TaskStatus.Succeeded && task_value(closed) is err)
    }
    balanced()
}
def owned_source_job() {
    return <- computation(TaskResultBuilder(type<int>)) {
        var events & = task_event_source(type<int>) |> use_resource
        let value=task_wait_event(events) |> bind
        return value
    }
}
def resource_checks() {
    {
        var inscope job <- owned_source_job()
        verify(task_poll(job)==TaskStatus.Waiting)
        verify(task_event_stats().sources==1 && task_event_stats().subscriptions==1)
        verify(task_cancel(job))
        balanced()
    }
    {
        var inscope unused <- owned_source_job()
        verify(task_cancel(unused))
        balanced()
    }
}
[export]
def main() {
    success_checks();balanced();cancellation_checks();balanced();timeout_checks();balanced();lifetime_checks()
    composition_checks();balanced();value_checks();balanced();resource_checks()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {
        success_checks();cancellation_checks();timeout_checks();lifetime_checks();composition_checks();value_checks();resource_checks();balanced()
        verify(heap_bytes_allocated()==baseline)
    }
    print("Task event checks OK\n")
}
