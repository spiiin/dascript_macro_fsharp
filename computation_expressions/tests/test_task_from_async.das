options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das
require daslib/async_boost
require daslib/strings_boost
var trace=""
var reached=0

[async]
def standard_value(n:int) : int {
    trace+="start;"
    await_next_frame()
    trace+="res;"
    yield n
    trace+="tail;"
}
[async]
def immediate() : int {trace+="immediate;";yield 3;trace+="tail;"}
[async]
def several() : int {
    trace+="one;";yield 1
    trace+="two;";yield 2
    await_next_frame()
    trace+="three;";yield 3
    trace+="end;"
}
[async]
def no_result() : int {await_next_frame()}
[async]
def standard_void() : void {trace+="v1;";await_next_frame();trace+="v2;"}
[async]
def standard_error(fail:bool) : variant<ok:int;error:string> {
    await_next_frame()
    yield fail ? result_error("denied",type<int>) : result_ok(7)
    trace+="error-tail;"
}
[async]
def standard_throw(afterResult:bool) : int {
    await_next_frame()
    if(afterResult) {yield 9}
    panic("native async failed")
    yield 0
}
[async]
def result_throw() : variant<ok:int;error:string> {
    await_next_frame()
    panic("result async threw")
    yield result_ok(0)
}
[async]
def empty_void() : void {}
[async]
def changing_result() : variant<ok:int;error:string> {
    yield result_error("intermediate",type<int>)
    await_next_frame()
    yield result_ok(11)
}
[async]
def nested() : int {
    let n <- await(standard_value(10))
    trace+="nested;"
    yield n+1
}

def order_checks() {
    trace=""
    var inscope task <- computation(TaskBuilder(type<int>)) {
        trace+="parent;"
        let a=task_from_async(standard_value(10)) |> bind
        trace+="bound;"
        let b=task_from_async(immediate()) |> bind
        return a+b
    }
    verify(trace=="")
    verify(task_poll(task)==TaskStatus.Waiting && trace=="parent;start;")
    verify(task_poll(task)==TaskStatus.Succeeded)
    verify(task_value(task)==13 && trace=="parent;start;res;tail;bound;immediate;tail;")
    verify(task_poll(task)==TaskStatus.Succeeded && trace=="parent;start;res;tail;bound;immediate;tail;")
    trace=""
    var inscope multiple <- task_from_async(several())
    verify(task_poll(multiple)==TaskStatus.Waiting && trace=="one;two;")
    verify(task_poll(multiple)==TaskStatus.Succeeded && task_value(multiple)==3 && trace=="one;two;three;end;")
    trace=""
    var inscope child <- task_from_async(nested())
    var status=task_poll(child)
    while(status==TaskStatus.Waiting) {status=task_poll(child)}
    verify(status==TaskStatus.Succeeded && task_value(child)==11)
    verify(trace=="start;res;tail;nested;")
    trace=""
    var inscope effect <- computation(TaskBuilder(type<int>)) {
        task_from_async(standard_void()) |> bind
        trace+="done;"
        return 5
    }
    verify(task_poll(effect)==TaskStatus.Waiting && trace=="v1;")
    verify(task_poll(effect)==TaskStatus.Succeeded && trace=="v1;v2;done;")
    var inscope empty <- task_from_async(empty_void())
    verify(task_poll(empty)==TaskStatus.Succeeded)
}
def error_checks() {
    reached=0;trace=""
    var inscope rejected <- computation(TaskResultBuilder(type<int>)) {
        let n=task_from_async(standard_error(true)) |> bind
        reached++
        return n+1
    }
    verify(task_poll(rejected)==TaskStatus.Waiting && reached==0)
    verify(task_poll(rejected)==TaskStatus.Succeeded && reached==0 && trace=="error-tail;")
    let failure=task_value(rejected)
    verify(failure is error && failure as error=="denied")
    var inscope accepted <- computation(TaskResultBuilder(type<int>)) {
        let n=task_from_async(standard_error(false)) |> bind
        reached++
        return n+1
    }
    verify(task_poll(accepted)==TaskStatus.Waiting)
    verify(task_poll(accepted)==TaskStatus.Succeeded && reached==1)
    let success=task_value(accepted)
    verify(success is ok && success as ok==8)
    for(afterResult in [false,true]) {
        var inscope failed <- computation(TaskBuilder(type<int>)) {
            let n=task_from_async(standard_throw(afterResult)) |> bind
            reached++
            return n
        }
        verify(task_poll(failed)==TaskStatus.Waiting)
        verify(task_poll(failed)==TaskStatus.Failed && reached==1)
        verify(starts_with(task_error(failed),"native async failed"))
    }
    var inscope missing <- task_from_async(no_result())
    verify(task_poll(missing)==TaskStatus.Waiting)
    verify(task_poll(missing)==TaskStatus.Failed)
    verify(starts_with(task_error(missing),"task_from_async: async completed without a result"))
    var inscope fault <- computation(TaskResultBuilder(type<int>)) {
        let n=task_from_async(result_throw()) |> bind
        reached++
        return n
    }
    verify(task_poll(fault)==TaskStatus.Waiting)
    verify(task_poll(fault)==TaskStatus.Failed && reached==1)
    verify(starts_with(task_error(fault),"result async threw"))
    var inscope finalResult <- computation(TaskResultBuilder(type<int>)) {
        let n=task_from_async(changing_result()) |> bind
        return n
    }
    verify(task_poll(finalResult)==TaskStatus.Waiting)
    verify(task_poll(finalResult)==TaskStatus.Succeeded)
    let finalValue=task_value(finalResult)
    verify(finalValue is ok && finalValue as ok==11)
}
[export]
def main() {order_checks();error_checks();print("Task async adapter checks OK\n")}
