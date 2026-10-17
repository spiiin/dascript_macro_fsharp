options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
var released=0
var completion=""
struct AssetData {items:array<int>}
def acquire() {var data:AssetData;data.items <- [1,2,3];return <- data}
def ce_dispose(var data:AssetData) {released++;delete data}
def load_asset(id,delay:int) {
    return <- computation(TaskBuilder(type<int>)) {
        var data & = acquire() |> use_resource
        task_delay_ms(delay) |> bind
        completion+="{id}"
        return id*10+length(data.items)
    }
}
def asset_jobs() {
    var tasks:array<typedecl(task_after_polls(0,0))>
    tasks |> emplace(load_asset(0,30))
    tasks |> emplace(load_asset(1,10))
    tasks |> emplace(load_asset(2,20))
    return <- tasks
}
[export]
def main() {
    var inscope scheduler <- task_scheduler(type<int>)
    var source <- computation(TaskBuilder(type<int>)) {
        var results & = task_when_all(asset_jobs()) |> bind
        // Completion order is 1,2,0; result indices still correspond to 0,1,2.
        verify(results[0]==3 && results[1]==13 && results[2]==23)
        return results[0]+results[1]+results[2]
    }
    let id=task_spawn(scheduler,source)
    verify(task_tick(scheduler,1000)==1)
    verify(task_tick(scheduler,1010)==1 && completion=="1")
    verify(task_tick(scheduler,1020)==1 && completion=="12")
    verify(task_tick(scheduler,1030)==0 && completion=="120")
    verify(task_value(scheduler,id)==39 && released==3)
    print("Task array demo OK\n")
}
