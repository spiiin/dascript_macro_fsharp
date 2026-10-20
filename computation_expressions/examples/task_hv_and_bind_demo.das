options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require ../lib/task_hv.das
require daslib/rtti
require daslib/jobque_boost
require daslib/fio
require daslib/strings_convert

def exchange(url:string;text:string) {
    return <- computation(TaskResultBuilder(type<string>)) {
        var socket & = hv_websocket() |> use_resource
        ws_connect(socket,url) |> bind
        ws_send_text(socket,text) |> bind
        let reply=ws_receive_text(socket) |> bind
        return reply
    }
}
def two_requests(urlA:string;urlB:string) {
    return <- computation(TaskResultBuilder(type<string>)) {
        let pair=exchange(urlA,"one") |> and_bind(exchange(urlB,"two")) |> bind
        return "A={pair.first}; B={pair.second}"
    }
}
def run_demo(urlA:string;urlB:string;cancel_after_ms:int=-1;timeout_ms:int=5000) {
    var inscope token <- cancellation_token()
    var inscope scheduler <- task_scheduler(type<$Result<string;string>>)
    let id=task_spawn(scheduler,task_with_cancellation(two_requests(urlA,urlB),token),TaskTimeout(after_ms=int64(timeout_ms)))
    let started=ref_time_ticks()
    while(task_status(scheduler,id)==TaskStatus.Created || task_status(scheduler,id)==TaskStatus.Waiting) {
        let now_ms=int64(get_time_usec(started)/1000)
        if(cancel_after_ms>=0 && now_ms>=int64(cancel_after_ms)) {cancellation_cancel(token)}
        task_tick(scheduler,now_ms)
        sleep(1u)
    }
    if(task_status(scheduler,id)==TaskStatus.Cancelled) {
        print(task_timed_out(scheduler,id) ? "Timeout\n" : "Cancelled\n")
    } elif(task_status(scheduler,id)==TaskStatus.Failed) {
        print("Exception: {task_error(scheduler,id)}\n")
    } else {
        let result=task_value(scheduler,id)
        verify(result is ok && result as ok=="A=one; B=two")
        if(result is ok) {print("{result as ok}\n")}
        else {print("Error: {result as err}\n")}
    }
    verify(hv_websocket_stats().active==0 && hv_websocket_stats().active_operations==0)
    return task_status(scheduler,id)
}
[export]
def main() {
    let port=to_int(get_env_variable("CE_HV_PORT"))
    verify(run_demo("ws://127.0.0.1:{port}/echo_a","ws://127.0.0.1:{port}/echo_b")==TaskStatus.Succeeded)
    verify(run_demo("ws://127.0.0.1:{port}/silent_a","ws://127.0.0.1:{port}/silent_b",50)==TaskStatus.Cancelled)
    verify(run_demo("ws://127.0.0.1:{port}/silent_c","ws://127.0.0.1:{port}/silent_d",-1,50)==TaskStatus.Cancelled)
    print("dasHV WebSocket and_bind demo OK\n")
}
