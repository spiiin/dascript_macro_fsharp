options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das
require daslib/rtti
var closed=0
struct AsyncSource {value:int}
struct AsyncRange {count:int}
def ce_source(builder:tuple<kind:TaskContext;element:auto>;source:AsyncSource) {return <- task_after_polls(0,source.value)}
def ce_source(builder:tuple<kind:TaskContext;element:auto>;source:AsyncRange) {return range(source.count)}
def arrays() {
    return <- computation(TaskBuilder(type<array<int>>)) {
        let n=task_after_polls(1,7) |> bind
        var values <- [n,n+1]
        return <- values
    }
}
[export]
def main() {
    var inscope adapted <- computation(TaskBuilder(type<int>)) {
        var total=0
        for(i in AsyncRange(count=3)) {let n=AsyncSource(value=i) |> bind;total+=n}
        return total
    }
    verify(task_poll(adapted)==TaskStatus.Succeeded && task_value(adapted)==3)
    var inscope empty <- computation(TaskBuilder(type<CeUnit>)) {}
    verify(task_poll(empty)==TaskStatus.Succeeded)
    var inscope unitResult <- computation(TaskResultBuilder(type<CeUnit>)) {
        task_after_polls(0,CeUnit()) |> bind
    }
    verify(task_poll(unitResult)==TaskStatus.Succeeded)
    var inscope forward <- computation(TaskBuilder(type<int>)) {
        return task_after_polls(1,9) |> return_from
    }
    verify(task_poll(forward)==TaskStatus.Waiting && task_poll(forward)==TaskStatus.Succeeded && task_value(forward)==9)
    var inscope task <- computation(TaskBuilder(type<array<int>>)) {
        var values & = arrays() |> bind
        task_after_polls(1,CeUnit()) |> bind
        values |> push(9)
        return <- values
    }
    verify(task_poll(task)==TaskStatus.Waiting)
    verify(task_poll(task)==TaskStatus.Waiting)
    verify(task_poll(task)==TaskStatus.Succeeded)
    var inscope value <- task_take(task)
    verify(length(value)==3 && value[0]==7 && value[2]==9)
    var inscope result <- computation(TaskResultBuilder(type<array<int>>)) {
        var values <- [1,2]
        return <- values
    }
    verify(task_poll(result)==TaskStatus.Succeeded)
    var inscope data <- task_value(result)
    verify(data is ok && length(data as ok)==2)
    print("Task extended checks OK\n")
}
