options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require ../lib/task_hv.das
require daslib/fio
require daslib/strings_convert
require daslib/rtti
require daslib/jobque_boost
require strings
var port=0
var markers=""
var continued=0
var receiving=0
var wall_start:int64

def url(path:string) {return "ws://127.0.0.1:{port}/{path}"}
def tick(var scheduler:auto;clock:int64=0l) {
    verify(get_time_usec(wall_start)<15000000)
    task_tick(scheduler,clock);sleep(1u)
}
def drive(var scheduler:auto;id:TaskId;clock:int64=0l) {
    while(task_status(scheduler,id)==TaskStatus.Created || task_status(scheduler,id)==TaskStatus.Waiting) {tick(scheduler,clock)}
}
def seen(var scheduler:auto;path:string) {
    while(!fexist("{markers}/{path}")) {tick(scheduler)}
}
def await_receiving(var scheduler:auto) {while(receiving==0) {tick(scheduler)}}

def echo(path:string="echo") {
    return <- computation(TaskResultBuilder(type<string>)) {
        var socket & = hv_websocket() |> use_resource
        ws_connect(socket,url(path)) |> bind
        ws_send_text(socket,"hello") |> bind
        let first=ws_receive_text(socket) |> bind
        ws_send_text(socket,"world") |> bind
        let second=ws_receive_text(socket) |> bind
        return "{first}/{second}"
    }
}
def waiting(path:string;connect_only:bool=false) {
    return <- computation(TaskResultBuilder(type<string>)) {
        var socket & = hv_websocket() |> use_resource
        ws_connect(socket,url(path)) |> bind
        if(!connect_only) {
            ws_send_text(socket,"wait") |> bind
            receiving++
            ws_receive_text(socket) |> bind
        }
        continued++
        return "unexpected"
    }
}
def balanced() {
    let stats=hv_websocket_stats()
    verify(stats.active==0 && stats.active_clients==0 && stats.active_operations==0)
    verify(stats.created==stats.released && stats.clients_started==stats.clients_stopped)
}
def echo_checks() {
    var inscope scheduler <- task_scheduler(type<variant<ok:string;error:string>>)
    let before=hv_websocket_stats()
    let id=task_spawn(scheduler,echo())
    verify(hv_websocket_stats().clients_started==before.clients_started)
    drive(scheduler,id)
    verify(task_status(scheduler,id)==TaskStatus.Succeeded)
    let value=task_value(scheduler,id)
    verify(value is ok && value as ok=="hello/world")
}
def cancellation_checks() {
    continued=0
    {
        var inscope token <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<variant<ok:string;error:string>>)
        let id=task_spawn(scheduler,task_with_cancellation(waiting("handshake_cancel",true),token))
        seen(scheduler,"handshake_cancel")
        verify(task_status(scheduler,id)==TaskStatus.Waiting)
        cancellation_cancel(token);drive(scheduler,id)
        verify(task_status(scheduler,id)==TaskStatus.Cancelled && continued==0)
    }
    balanced();receiving=0
    {
        var inscope token <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<variant<ok:string;error:string>>)
        let id=task_spawn(scheduler,task_with_cancellation(waiting("silent_cancel"),token))
        await_receiving(scheduler)
        cancellation_cancel(token);drive(scheduler,id)
        verify(task_status(scheduler,id)==TaskStatus.Cancelled && continued==0)
    }
    balanced()
}
def timeout_checks() {
    continued=0
    {
        var inscope scheduler <- task_scheduler(type<variant<ok:string;error:string>>)
        let id=task_spawn(scheduler,waiting("handshake_timeout",true),TaskTimeout(after_ms=5))
        seen(scheduler,"handshake_timeout")
        verify(task_status(scheduler,id)==TaskStatus.Waiting)
        tick(scheduler,5l)
        verify(task_timed_out(scheduler,id) && task_status(scheduler,id)==TaskStatus.Cancelled && continued==0)
    }
    balanced();receiving=0
    {
        var inscope scheduler <- task_scheduler(type<variant<ok:string;error:string>>)
        let id=task_spawn(scheduler,waiting("silent_timeout"),TaskTimeout(after_ms=5))
        await_receiving(scheduler);tick(scheduler,5l)
        verify(task_timed_out(scheduler,id) && task_status(scheduler,id)==TaskStatus.Cancelled && continued==0)
    }
    balanced()
}
def lifetime_checks() {
    {
        var inscope explicitResult <- computation(TaskBuilder(type<bool>)) {
            var socket & = hv_websocket() |> use_resource
            let outcome=ws_connect(socket,"invalid-url") |> bind
            return outcome is error
        }
        verify(task_poll(explicitResult)==TaskStatus.Succeeded && task_value(explicitResult))
    }
    balanced()
    {
        var socket <- hv_websocket()
        var job <- ws_connect(socket,url("echo_unused"))
        delete socket
        verify(task_poll(job)==TaskStatus.Succeeded && task_value(job) is error)
        delete job
    }
    balanced()
    {
        var inscope socket <- hv_websocket()
        let before=hv_websocket_stats().clients_started
        var cancelled <- ws_connect(socket,url("echo_unstarted"))
        verify(task_cancel(cancelled))
        delete cancelled
        verify(hv_websocket_stats().clients_started==before)
    }
    balanced()
}
def failure(path:string;config:HvWebSocketConfig=HvWebSocketConfig()) {
    return <- computation(TaskResultBuilder(type<string>)) {
        var socket & = hv_websocket(config) |> use_resource
        ws_connect(socket,url(path)) |> bind
        let text=ws_receive_text(socket) |> bind
        continued++
        return text
    }
}
def pending_owner_checks() {
    {
        var socket <- hv_websocket()
        var inscope scheduler <- task_scheduler(type<variant<ok:CeUnit;error:string>>)
        let id=task_spawn(scheduler,ws_connect(socket,url("handshake_owner")))
        seen(scheduler,"handshake_owner")
        // The operation keeps its data alive, but deleting the owner closes transport.
        delete socket
        drive(scheduler,id)
        verify(task_status(scheduler,id)==TaskStatus.Succeeded && task_value(scheduler,id) is error)
    }
    balanced()
    {
        var inscope socket <- hv_websocket()
        var inscope scheduler <- task_scheduler(type<variant<ok:CeUnit;error:string>>)
        let id=task_spawn(scheduler,ws_connect(socket,url("handshake_busy")))
        seen(scheduler,"handshake_busy")
        var inscope other <- ws_send_text(socket,"too early")
        verify(task_poll(other)==TaskStatus.Succeeded)
        let rejected=task_value(other)
        verify(rejected is error && rejected as error=="WebSocket: another operation is active")
        verify(hv_websocket_stats().active_clients==1)
        verify(task_status(scheduler,id)==TaskStatus.Waiting)
        task_cancel(scheduler,id)
    }
    balanced()
}
def error_checks() {
    continued=0
    for(path in fixed_array("peer_close","binary","oversize")) {
        var inscope scheduler <- task_scheduler(type<variant<ok:string;error:string>>)
        let id=task_spawn(scheduler,failure(path,HvWebSocketConfig(max_message_bytes=16)))
        drive(scheduler,id)
        verify(task_status(scheduler,id)==TaskStatus.Succeeded && task_value(scheduler,id) is error && continued==0)
    }
    balanced()
    {
        var inscope scheduler <- task_scheduler(type<variant<ok:string;error:string>>)
        var job <- computation(TaskResultBuilder(type<string>)) {
            var socket & = hv_websocket() |> use_resource
            ws_connect(socket,url("fault")) |> bind
            panic("WebSocket driver fault")
            return ""
        }
        let id=task_spawn(scheduler,job);drive(scheduler,id)
        verify(task_status(scheduler,id)==TaskStatus.Failed && starts_with(task_error(scheduler,id),"WebSocket driver fault"))
    }
    balanced()
}
[export]
def main() {
    port=to_int(get_env_variable("CE_HV_PORT"));markers=get_env_variable("CE_HV_MARKERS");wall_start=ref_time_ticks()
    lifetime_checks();echo_checks();balanced()
    cancellation_checks();timeout_checks();error_checks();pending_owner_checks()
    echo_checks();balanced()
    let baseline=heap_bytes_allocated()
    for(i in range(12)) {echo_checks();lifetime_checks();balanced()}
    verify(heap_bytes_allocated()==baseline)
    print("dasHV WebSocket Task checks OK\n")
}
