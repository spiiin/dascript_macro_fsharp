options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require daslib/rtti
require daslib/async_boost
var closed=0
[async]
def native_owned() : array<int> {
    await_next_frame()
    var data <- [3,4]
    yield <- data
}
def array_job(n:int;waits:int=0) {
    return <- computation(TaskBuilder(type<array<int>>)) {
        var data <- [n,n+1]
        task_after_polls(waits,CeUnit()) |> bind
        return <- data
    }
}
def result_job(n:int;waits:int=0;fail:bool=false) {
    return <- computation(TaskResultBuilder(type<array<int>>)) {
        var data <- [n,n+1]
        task_after_polls(waits,CeUnit()) |> bind
        if(fail) {let ignored=task_after_polls(0,result_error("denied",type<int>)) |> bind}
        return <- data
    }
}
def checks() {
    {
        var inscope pair <- (index=4,value <- [1,2])
        var inscope wrapped <- move_ok(pair)
        verify(empty(pair.value) && wrapped is ok && (wrapped as ok).value[0]==1)
    }
    {
        var inscope source <- task_from_async(native_owned())
        verify(task_poll(source)==TaskStatus.Waiting && task_poll(source)==TaskStatus.Succeeded)
        var inscope data <- task_take(source)
        verify(data[0]==3 && data[1]==4)
    }
    {
        var inscope task <- computation(TaskBuilder(type<array<int>>)) {
            var p & = array_job(1,1) |> and_bind(array_job(3)) |> bind
            p.first |> push(p.second[0])
            return <- p.first
        }
        verify(task_poll(task)==TaskStatus.Waiting && task_poll(task)==TaskStatus.Succeeded)
        var inscope data <- task_take(task)
        verify(length(data)==3 && data[2]==3)
    }
    {
        var inscope task <- computation(TaskResultBuilder(type<int>)) {
            var pair & = result_job(3,1) |> and_bind(result_job(5)) |> bind
            return pair.first[0]+pair.second[0]
        }
        verify(task_poll(task)==TaskStatus.Waiting && task_poll(task)==TaskStatus.Succeeded)
        verify(task_value(task) is ok && task_value(task) as ok==8)
    }
    {
        var inscope task <- computation(TaskResultBuilder(type<int>)) {
            let p=task_after_polls(1,CeUnit()) |> and_bind(task_after_polls(0,result_ok(5))) |> bind
            return p.second
        }
        verify(task_poll(task)==TaskStatus.Waiting && task_poll(task)==TaskStatus.Succeeded)
        let result=task_value(task)
        verify(result is ok && result as ok==5)
    }
    {
        var jobs:array<typedecl(array_job(0))>
        jobs |> emplace(array_job(10,1));jobs |> emplace(array_job(20))
        var inscope task <- task_when_all(jobs)
        verify(task_poll(task)==TaskStatus.Waiting && task_poll(task)==TaskStatus.Succeeded)
        var inscope data <- task_take(task)
        verify(data[0][0]==10 && data[1][0]==20)
    }
    {
        var jobs:array<typedecl(result_job(0))>
        jobs |> emplace(result_job(10,1));jobs |> emplace(result_job(20))
        var inscope task <- task_result_when_all(jobs)
        verify(task_poll(task)==TaskStatus.Waiting && task_poll(task)==TaskStatus.Succeeded)
        var inscope data <- task_take(task)
        verify(data is ok && (data as ok)[0][0]==10 && (data as ok)[1][0]==20)
    }
    {
        var jobs:array<typedecl(result_job(0))>
        jobs |> emplace(result_job(10,2));jobs |> emplace(result_job(20,0,true))
        var inscope task <- task_result_when_all(jobs)
        verify(task_poll(task)==TaskStatus.Succeeded)
        var inscope data <- task_take(task)
        verify(data is error && data as error=="denied")
    }
    {
        var inscope raced <- task_result_race(result_job(1,3),result_job(2))
        verify(task_poll(raced)==TaskStatus.Succeeded)
        var inscope data <- task_take(raced)
        verify(data is ok && (data as ok).index==1 && (data as ok).value[0]==2)
    }
    {
        var inscope scheduler <- task_scheduler(type<array<int>>)
        let id=task_spawn(scheduler,array_job(8,1))
        verify(task_tick(scheduler,0)==1 && task_tick(scheduler,1)==0)
        var inscope data <- task_value(scheduler,id)
        verify(data[0]==8)
        var inscope taken <- task_take(scheduler,id)
        verify(taken[0]==8 && task_count(scheduler)==0)
        task_scheduler_close(scheduler)
    }
    {
        var inscope handle <- task_share(array_job(6,1))
        var inscope a <- ce_task_source(handle)
        var inscope b <- ce_task_source(handle)
        verify(task_poll(a)==TaskStatus.Waiting && task_poll(b)==TaskStatus.Succeeded)
        verify(task_poll(a)==TaskStatus.Succeeded)
        var inscope first <- task_take(a)
        var inscope second <- task_take(b)
        first[0]=99
        verify(second[0]==6)
    }
    {
        var inscope task <- array_job(1,10)
        verify(task_poll(task)==TaskStatus.Waiting && task_cancel(task))
    }
    {
        var inscope task <- computation(TaskBuilder(type<int>)) {
            var inscope first <- task_after_polls(1,5)
            var inscope second <- task_after_polls(0,6)
            let p=first |> and_bind(second) |> bind
            return p.first+p.second
        }
        verify(task_poll(task)==TaskStatus.Waiting && task_poll(task)==TaskStatus.Succeeded && task_value(task)==11)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(24)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task owned checks OK\n")
}
