options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require ../lib/task_jobque.das
require daslib/rtti
def compute(n:int) {var total=0;for(i in range(n)) {total+=i};return total}
[export]
def main() {
 with_job_que() {
  var inscope queue <- task_job_queue()
  var inscope runtime <- task_runtime()
  var inscope ticket <- task_spawn(runtime,task_jobque(queue,100,@@compute))
  for(i in range(100000)) {
   task_tick(runtime,i)
   if(task_status(ticket)==TaskStatus.Succeeded) {break}
  }
  verify(task_status(ticket)==TaskStatus.Succeeded && task_value(ticket) as ok==4950)
  task_jobque_collect(queue)
 }
 verify(task_jobque_channels()==0)
 print("Task jobque checks OK\n")
}
