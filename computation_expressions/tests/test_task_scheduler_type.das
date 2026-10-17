options gen2
require ../lib/task_scheduler.das
[export]
def main() {
    var inscope scheduler <- task_scheduler(type<int>)
    let id=task_spawn(scheduler,task_after_polls(0,"wrong payload"))
}
