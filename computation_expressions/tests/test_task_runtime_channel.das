options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require ../lib/task_channel.das
require daslib/rtti
[export]
def main() {
 var inscope runtime <- task_runtime()
 var inscope a <- task_spawn(runtime,task_after_polls(1,42))
 var inscope b <- task_spawn(runtime,task_after_polls(0,"hello"))
 task_tick(runtime,0);verify(task_status(b)==TaskStatus.Succeeded)
 task_tick(runtime,1);verify(task_value(a)==42 && task_value(b)=="hello")
 var inscope ch <- task_channel(type<int>,1)
 var inscope send <- task_channel_send(ch,7)
 var inscope recv <- task_channel_receive(ch)
 task_poll(send);task_poll(recv)
 verify((recv.value as ok) as some==7)
 task_channel_close(ch)
 var inscope end <- task_channel_receive(ch);task_poll(end)
 verify((end.value as ok) is none)
 print("Task runtime channel checks OK\n")
}
