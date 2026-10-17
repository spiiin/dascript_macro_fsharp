options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require ../lib/task_hv.das
require daslib/fio
require daslib/strings_convert
require daslib/rtti
require daslib/jobque_boost

def echo(url:string) {
    return <- computation(TaskResultBuilder(type<string>)) {
        var socket & = hv_websocket() |> use_resource
        ws_connect(socket,url) |> bind
        ws_send_text(socket,"hello") |> bind
        let reply=ws_receive_text(socket) |> bind
        return "Reply: {reply}"
    }
}
[export]
def main() {
    let port=to_int(get_env_variable("CE_HV_PORT"))
    var inscope token <- cancellation_token()
    var inscope scheduler <- task_scheduler(type<variant<ok:string;error:string>>)
    let id=task_spawn(scheduler,task_with_cancellation(echo("ws://127.0.0.1:{port}/echo_demo"),token),TaskTimeout(after_ms=5000))
    let started=ref_time_ticks()
    while(task_status(scheduler,id)==TaskStatus.Created || task_status(scheduler,id)==TaskStatus.Waiting) {
        task_tick(scheduler,int64(get_time_usec(started)/1000));sleep(1u)
    }
    verify(task_status(scheduler,id)==TaskStatus.Succeeded)
    let response=task_value(scheduler,id)
    verify(response is ok && response as ok=="Reply: hello")
    verify(hv_websocket_stats().active==0 && hv_websocket_stats().active_operations==0)
    print("dasHV WebSocket echo demo OK\n")
}
