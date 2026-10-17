options gen2
require ../lib/task_builder.das
require daslib/async_boost
[async]
def owned_values() : array<int> {var values <- [1,2];yield <- values}
[export]
def main() {
    var inscope task <- task_from_async(owned_values())
    verify(task_poll(task)==TaskStatus.Succeeded)
    var inscope values <- task_take(task)
    verify(length(values)==2 && values[0]==1 && values[1]==2)
    print("Task async move checks OK\n")
}
