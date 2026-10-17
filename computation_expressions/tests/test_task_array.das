options gen2
require ../lib/computation_macro.das
require ../lib/task_combinators.das
require ../lib/task_scheduler.das
var trace=""
var continued=0
def observed(name:string; waits:int; value:int) {
    return <- computation(TaskBuilder(type<int>)) {
        trace+=name
        task_after_polls(waits,CeUnit()) |> bind
        trace+="!"+name
        return value
    }
}
def jobs() {
    var result:array<typedecl(task_after_polls(0,0))>
    result |> emplace(task_after_polls(2,10))
    result |> emplace(task_after_polls(0,20))
    result |> emplace(task_after_polls(1,30))
    return <- result
}
def result_jobs() {
    var resultJobs:array<typedecl(task_after_polls(0,result_ok(0)))>
    resultJobs |> emplace(task_after_polls(0,result_error("domain",type<int>)))
    resultJobs |> emplace(task_after_polls(1,result_ok(9)))
    return <- resultJobs
}
def unit_jobs() {
    var units:array<typedecl(task_after_polls(0,CeUnit()))>
    units |> emplace(task_after_polls(0,CeUnit()))
    units |> emplace(task_after_polls(1,CeUnit()))
    return <- units
}
[export]
def main() {
    var children <- jobs()
    var inscope task <- task_when_all(children)
    verify(empty(children))
    verify(task_poll(task)==TaskStatus.Waiting)
    verify(task_poll(task)==TaskStatus.Waiting)
    verify(task_poll(task)==TaskStatus.Succeeded)
    var inscope values <- task_value(task)
    verify(length(values)==3 && values[0]==10 && values[1]==20 && values[2]==30)
    var inscope parent <- computation(TaskBuilder(type<int>)) {
        var results & = task_when_all(jobs()) |> bind
        return results[0]+results[1]+results[2]
    }
    verify(task_poll(parent)==TaskStatus.Waiting)
    verify(task_poll(parent)==TaskStatus.Waiting)
    verify(task_poll(parent)==TaskStatus.Succeeded && task_value(parent)==60)
    var inscope scheduler <- task_scheduler(type<array<int>>)
    let id=task_spawn(scheduler,task_when_all(jobs()))
    verify(task_tick(scheduler,0)==1 && task_tick(scheduler,1)==1 && task_tick(scheduler,2)==0)
    var inscope scheduled <- task_value(scheduler,id)
    verify(scheduled[0]==10 && scheduled[1]==20 && scheduled[2]==30)
    scheduled[0]=99
    var inscope again <- task_value(scheduler,id)
    verify(again[0]==10)
    verify(task_forget(scheduler,id) && scheduled[1]==20 && again[2]==30)
    var emptyJobs:array<typedecl(task_after_polls(0,0))>
    var inscope emptyTask <- task_when_all(emptyJobs)
    verify(task_poll(emptyTask)==TaskStatus.Succeeded)
    var inscope emptyValues <- task_value(emptyTask)
    verify(empty(emptyValues))
    var observedJobs:array<typedecl(task_after_polls(0,0))>
    observedJobs |> emplace(observed("a",2,10))
    observedJobs |> emplace(observed("b",0,20))
    observedJobs |> emplace(observed("c",1,30))
    var inscope observedTask <- task_when_all(observedJobs)
    verify(trace=="")
    verify(task_poll(observedTask)==TaskStatus.Waiting && trace=="ab!bc")
    verify(task_poll(observedTask)==TaskStatus.Waiting && trace=="ab!bc!c")
    verify(task_poll(observedTask)==TaskStatus.Succeeded && trace=="ab!bc!c!a")
    var readyJobs:array<typedecl(task_after_polls(0,0))>
    var ready <- task_after_polls(0,77)
    verify(task_poll(ready)==TaskStatus.Succeeded)
    readyJobs |> emplace(ready)
    var inscope readyAll <- task_when_all(readyJobs)
    verify(task_poll(readyAll)==TaskStatus.Succeeded)
    var inscope readyValues <- task_value(readyAll)
    verify(length(readyValues)==1 && readyValues[0]==77)
    var inscope loanScheduler <- task_scheduler(type<int>)
    var loanTask <- computation(TaskBuilder(type<int>)) {
        var results & = task_when_all(jobs()) |> bind
        task_delay_ms(10) |> bind
        return results[0]+results[2]
    }
    let loan=task_spawn(loanScheduler,loanTask)
    verify(task_tick(loanScheduler,0)==1 && task_tick(loanScheduler,1)==1 && task_tick(loanScheduler,2)==1)
    verify(task_tick(loanScheduler,12)==0 && task_value(loanScheduler,loan)==40)
    var inscope domain <- computation(TaskResultBuilder(type<int>)) {
        var results & = task_when_all(result_jobs()) |> bind
        verify(results[0] is error && results[0] as error=="domain")
        continued++
        return results[1] as ok
    }
    verify(task_poll(domain)==TaskStatus.Waiting)
    verify(task_poll(domain)==TaskStatus.Succeeded && continued==1)
    let domainValue=task_value(domain)
    verify(domainValue is ok && domainValue as ok==9)
    var strings:array<typedecl(task_after_polls(0,""))>
    strings |> emplace(task_after_polls(1,"second"))
    strings |> emplace(task_after_polls(0,"first"))
    var inscope stringTask <- task_when_all(strings)
    verify(task_poll(stringTask)==TaskStatus.Waiting && task_poll(stringTask)==TaskStatus.Succeeded)
    var inscope stringValues <- task_value(stringTask)
    delete stringTask
    verify(stringValues[0]=="second" && stringValues[1]=="first")
    var inscope unitTask <- task_when_all(unit_jobs())
    verify(task_poll(unitTask)==TaskStatus.Waiting && task_poll(unitTask)==TaskStatus.Succeeded)
    var inscope unitValues <- task_value(unitTask)
    verify(length(unitValues)==2)
    var inscope voidBatch <- computation(TaskBuilder(type<int>)) {
        task_when_all(unit_jobs()) |> bind
        return 5
    }
    verify(task_poll(voidBatch)==TaskStatus.Waiting && task_poll(voidBatch)==TaskStatus.Succeeded)
    verify(task_value(voidBatch)==5)
    print("Task array checks OK\n")
}
