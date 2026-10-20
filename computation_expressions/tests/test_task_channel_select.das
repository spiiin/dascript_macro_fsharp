options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require ../lib/task_channel.das
require daslib/rtti

var input:typedecl(task_channel(type<string>,4))
var commands:typedecl(task_channel(type<string>,4))

def router() {
    return <- computation(TaskResultBuilder(type<string>)) {
        var log=""
        var open=2
        while(open>0) {
            let pick=task_channel_select(input,commands) |> bind
            if(pick.value is none) {open--;continue}
            log+="{pick.index}:{pick.value as some};"
        }
        return log
    }
}

def checks() {
    {
        var inscope a <- task_channel(type<int>,2)
        var inscope b <- task_channel(type<int>,2)
        // Waits until either channel has an item.
        var inscope pick <- task_channel_select(a,b)
        verify(task_poll(pick)==TaskStatus.Waiting && task_channel_waiters(a)==1 && task_channel_waiters(b)==1)
        verify(task_channel_try_send(b,20))
        verify(task_poll(pick)==TaskStatus.Succeeded)
        verify((pick.value as ok).index==1 && (pick.value as ok).value as some==20)
        // The winner deregisters from the other channel immediately.
        verify(task_channel_waiters(a)==0 && task_channel_waiters(b)==0)
        // Both ready: lower index wins, the other item stays queued.
        task_channel_try_send(a,1);task_channel_try_send(b,2)
        var inscope both <- task_channel_select(a,b)
        task_poll(both)
        verify((both.value as ok).index==0 && task_channel_count(b)==1 && task_channel_count(a)==0)
        // Cancelling a pending select releases both registrations and loses nothing.
        var inscope drained <- task_channel_receive(b);task_poll(drained)
        var inscope pending <- task_channel_select(a,b)
        task_poll(pending);verify(task_cancel(pending))
        verify(task_channel_waiters(a)==0 && task_channel_waiters(b)==0)
        task_channel_try_send(a,7)
        var inscope plain <- task_channel_receive(a);task_poll(plain)
        verify((plain.value as ok) as some==7)
    }
    {
        // FIFO among readers: an earlier plain receive is served first.
        var inscope a <- task_channel(type<int>,2)
        var inscope b <- task_channel(type<int>,2)
        var inscope first <- task_channel_receive(a);task_poll(first)
        var inscope pick <- task_channel_select(a,b);task_poll(pick)
        task_channel_try_send(a,1)
        task_poll(first);task_poll(pick)
        verify((first.value as ok) as some==1 && pick.status==TaskStatus.Waiting)
        task_channel_try_send(a,2)
        task_poll(pick)
        verify((pick.value as ok).index==0 && (pick.value as ok).value as some==2)
    }
    {
        // Closed and failed channels; three-way select.
        var inscope a <- task_channel(type<int>,1)
        var inscope b <- task_channel(type<int>,1)
        var inscope c <- task_channel(type<int>,1)
        task_channel_close(b)
        var inscope closed <- task_channel_select(a,b,c);task_poll(closed)
        verify((closed.value as ok).index==1 && (closed.value as ok).value is none)
        task_channel_try_send(c,3)
        var inscope d <- task_channel(type<int>,1)
        var inscope third <- task_channel_select(a,c,d);task_poll(third)
        verify((third.value as ok).index==1 && (third.value as ok).value as some==3)
        task_channel_fail(a,"broken")
        var inscope failed <- task_channel_select(a,c);task_poll(failed)
        verify(failed.value is err && failed.value as err=="broken")
    }
    {
        // Router task in a runtime merges two producers until both close.
        input <- task_channel(type<string>,4)
        commands <- task_channel(type<string>,4)
        var inscope runtime <- task_runtime()
        var inscope route <- task_spawn(runtime,router())
        task_tick(runtime,0)
        task_channel_try_send(input,"up");task_channel_try_send(commands,"save")
        task_tick(runtime,1);task_tick(runtime,2)
        task_channel_try_send(input,"down")
        task_channel_close(commands);task_channel_close(input)
        for(t in range(3,10)) {task_tick(runtime,t)}
        verify(task_value(route) is ok && task_value(route) as ok=="0:up;1:save;0:down;")
        delete runtime
        delete input
        delete commands
    }
}

[export]
def main() {
    checks();let baseline=heap_bytes_allocated()
    for(i in range(5)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task channel select checks OK\n")
}
