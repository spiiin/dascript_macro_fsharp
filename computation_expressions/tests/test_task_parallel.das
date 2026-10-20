options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require ../lib/task_parallel.das
require daslib/rtti
var attempts=0
[export]
def main() {
 var inscope sem <- task_semaphore(1)
 var inscope a <- task_semaphore_acquire(sem)
 var inscope b <- task_semaphore_acquire(sem)
 task_poll(a);task_poll(b)
 verify(a.status==TaskStatus.Succeeded && b.status==TaskStatus.Waiting)
 task_semaphore_release(sem);delete a
 task_poll(b);verify(b.status==TaskStatus.Succeeded)
 task_semaphore_release(sem);delete b
 var inscope retry <- task_retry(@(attempt:int) {attempts++;return <- task_after_polls(0,attempt<3 ? result_error("again",type<int>) : result_ok(42))},3)
 for(i in range(10)) {task_poll(retry)}
 verify(retry.value as ok==42 && attempts==3)
 var children:array<typedecl(task_after_polls(0,result_ok(1)))>
 children |> emplace(task_after_polls(0,result_error("no",type<int>)))
 children |> emplace(task_after_polls(1,result_ok(7)))
 var inscope first <- task_first_success(children)
 task_poll(first);task_poll(first);verify(first.value as ok==7)
 var inputs <- [3,2,1]
 var inscope all <- task_when_all_limited(inputs,2,@(i:int) {return <- task_after_polls(i,i*10)})
 for(i in range(10)) {task_poll(all)}
 verify(all.status==TaskStatus.Succeeded && all.value[0]==30 && all.value[1]==20 && all.value[2]==10)
 var inputs2 <- [1,2]
 var inscope results <- task_result_when_all_limited(inputs2,1,@(i:int) {return <- task_after_polls(0,result_ok(i))})
 for(i in range(4)) {task_poll(results)}
 verify(results.status==TaskStatus.Succeeded && length(results.value as ok)==2)
 print("Task parallel checks OK\n")
}
