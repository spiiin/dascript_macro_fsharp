options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require ../lib/task_channel.das
require daslib/rtti

def checks() {
    {
        var inscope ch <- task_channel(type<int>,1)
        verify(task_channel_try_send(ch,1))
        var inscope a <- task_channel_send(ch,2)
        var inscope b <- task_channel_send(ch,3)
        task_poll(a);task_poll(b);verify(task_channel_waiters(ch)==2)
        task_cancel(a);verify(task_channel_waiters(ch)==1)
        var inscope first <- task_channel_receive(ch);task_poll(first)
        verify((first.value as ok) as some==1)
        task_poll(b);verify(b.status==TaskStatus.Succeeded && task_channel_waiters(ch)==0)
        var inscope second <- task_channel_receive(ch);task_poll(second)
        verify((second.value as ok) as some==3)
        var inscope r1 <- task_channel_receive(ch)
        var inscope r2 <- task_channel_receive(ch)
        task_poll(r1);task_poll(r2)
        verify(task_channel_try_send(ch,10))
        task_poll(r2);verify(r2.status==TaskStatus.Waiting)
        task_cancel(r1);task_poll(r2);verify((r2.value as ok) as some==10)
        task_channel_close(ch)
        var inscope end <- task_channel_receive(ch);task_poll(end)
        verify((end.value as ok) is none)
        var inscope denied <- task_channel_send(ch,42);task_poll(denied)
        verify(denied.value is err)
    }
    {
        var inscope ch <- task_channel(type<array<int>>,1)
        var inscope data <- [1,2,3]
        var inscope send <- task_channel_send_move(ch,data)
        verify(empty(data));task_poll(send)
        var inscope receive <- task_channel_receive(ch);task_poll(receive)
        var inscope value <- task_take(receive)
        verify(((value as ok) as some)[2]==3)
        var inscope pending <- task_channel_send_move(ch,[4,5])
        task_cancel(pending)
        verify(task_channel_count(ch)==0 && task_channel_waiters(ch)==0)
        verify(task_channel_try_send_move(ch,[6,7]))
        task_channel_fail(ch,"broken")
        verify(task_channel_count(ch)==0)
        var inscope failed <- task_channel_receive(ch);task_poll(failed)
        verify(failed.value is err && failed.value as err=="broken")
    }
    {
        var inscope ch <- task_channel(type<int>,1)
        var inscope waiting <- task_channel_receive(ch)
        delete ch // Wait owns a lease; owner destruction closes the channel.
        task_poll(waiting);verify((waiting.value as ok) is none)
    }
    {
        var inscope ch <- task_channel(type<int>,1)
        var inscope runtime <- task_runtime()
        var inscope receive <- task_spawn(runtime,task_channel_receive(ch),TaskTimeout(after_ms=5))
        task_tick(runtime,100);verify(task_channel_waiters(ch)==1)
        task_tick(runtime,105)
        verify(task_timed_out(runtime,receive) && task_status(receive)==TaskStatus.Cancelled && task_channel_waiters(ch)==0)
        verify(task_channel_try_send(ch,5))
        var inscope send <- task_spawn(runtime,task_channel_send(ch,7),TaskTimeout(after_ms=5))
        task_tick(runtime,105);verify(task_channel_waiters(ch)==1)
        task_tick(runtime,110)
        verify(task_status(send)==TaskStatus.Cancelled && task_channel_waiters(ch)==0 && task_channel_count(ch)==1)
    }
}
[export]
def main() {
    checks();let baseline=heap_bytes_allocated()
    for(i in range(5)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task channel lifetime checks OK\n")
}
