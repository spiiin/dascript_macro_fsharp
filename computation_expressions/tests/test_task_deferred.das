options gen2
require ../lib/deferred_computation.das
require ../lib/task_builder.das
require daslib/rtti
require strings
var cleaned=0
def checks() {
    cleaned=0
    var first:typedecl(task_after_polls(0,0))
    var second:typedecl(task_after_polls(0,0))
    {
        var inscope data <- [3,4]
        var inscope saved <- deferred(TaskBuilder(type<int>),data) $(items) {
            try_finally($ {
                task_after_polls(1,CeUnit()) |> bind
                return items[0]+items[1]
            },$ {cleaned++})
        }
        data[0]=99
        first <- run_deferred(saved)
        second <- run_deferred(saved)
    }
    verify(task_poll(first)==TaskStatus.Waiting && task_poll(second)==TaskStatus.Waiting)
    verify(task_poll(first)==TaskStatus.Succeeded && task_value(first)==7)
    verify(task_cancel(second) && cleaned==2)
    delete first;delete second
    {
        var inscope saved <- deferred(TaskBuilder(type<int>),[8,9]) $(items) {
            task_after_polls(1,CeUnit()) |> bind
            panic("deferred task failure")
            return items[0]
        }
        // An unopened source must release its run snapshot as well.
        var unopened <- run_deferred(saved)
        delete unopened
        var inscope failed <- run_deferred(saved)
        verify(task_poll(failed)==TaskStatus.Waiting)
        verify(task_poll(failed)==TaskStatus.Failed)
        verify(starts_with(task_error(failed),"deferred task failure"))
    }
    {
        var inscope saved <- deferred(TaskResultBuilder(type<array<int>>),[1,2,3]) $(items) {
            var inscope data <- clone(items)
            task_after_polls(1,CeUnit()) |> bind
            return <- data
        }
        var inscope run <- run_deferred(saved)
        verify(task_poll(run)==TaskStatus.Waiting)
        verify(task_poll(run)==TaskStatus.Succeeded)
        var inscope value <- task_take(run)
        verify(value is ok && length(value as ok)==3)
        var inscope another <- run_deferred(saved)
        verify(task_poll(another)==TaskStatus.Waiting)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(24)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task deferred checks OK\n")
}
