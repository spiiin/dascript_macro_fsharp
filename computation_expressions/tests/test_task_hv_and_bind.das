options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require ../lib/task_hv.das
require daslib/fio
require daslib/strings_convert
require daslib/rtti
require daslib/jobque_boost
var port=0
var markers=""
var reading=0
var children_continued=0
var parent_continued=0
var started:int64

def watchdog() {verify(get_time_usec(started)<15000000)}
def tick(var scheduler:auto;clock:int64=0l) {watchdog();task_tick(scheduler,clock);sleep(1u)}
def drive(var scheduler:auto;id:TaskId) {
    while(task_status(scheduler,id)==TaskStatus.Created || task_status(scheduler,id)==TaskStatus.Waiting) {tick(scheduler)}
}
def wait_closed(path:string) {
    // Check peer-observed closure before the daslang process exits.
    while(!fexist("{markers}/closed_{path}")) {watchdog();sleep(1u)}
}
def balanced() {
    let s=hv_websocket_stats()
    verify(s.active==0 && s.active_clients==0 && s.active_operations==0)
    verify(s.created==s.released && s.clients_started==s.clients_stopped && s.operations_created==s.operations_released)
}
def exchange(path:string;text:string) {
    return <- computation(TaskResultBuilder(type<string>)) {
        var socket & = hv_websocket() |> use_resource
        ws_connect(socket,"ws://127.0.0.1:{port}/{path}") |> bind
        ws_send_text(socket,text) |> bind
        reading++
        let reply=ws_receive_text(socket) |> bind
        children_continued++
        return reply
    }
}
def pair(left:string;right:string) {
    return <- computation(TaskResultBuilder(type<string>)) {
        let replies=exchange(left,"one") |> and_bind(exchange(right,"two")) |> bind
        parent_continued++
        return "{replies.first}/{replies.second}"
    }
}
def both_waiting(var scheduler:auto;id:TaskId) {
    while(reading<2) {
        verify(task_status(scheduler,id)==TaskStatus.Created || task_status(scheduler,id)==TaskStatus.Waiting)
        tick(scheduler)
    }
    verify(task_status(scheduler,id)==TaskStatus.Waiting)
    verify(hv_websocket_stats().active_clients==2)
}
def reset() {reading=0;children_continued=0;parent_continued=0}
def success_checks(round:int) {
    reset()
    let left="echo_pair_left_{round}"
    let right="echo_pair_right_{round}"
    {
        var inscope scheduler <- task_scheduler(type<$Result<string;string>>)
        let id=task_spawn(scheduler,pair(left,right))
        drive(scheduler,id)
        verify(task_status(scheduler,id)==TaskStatus.Succeeded)
        let result=task_value(scheduler,id)
        verify(result is ok && result as ok=="one/two")
        verify(children_continued==2 && parent_continued==1)
        balanced();wait_closed(left);wait_closed(right)
    }
}
def cancellation_checks(round:int) {
    reset()
    let left="silent_pair_cancel_left_{round}"
    let right="silent_pair_cancel_right_{round}"
    {
        var inscope token <- cancellation_token()
        var inscope scheduler <- task_scheduler(type<$Result<string;string>>)
        let id=task_spawn(scheduler,task_with_cancellation(pair(left,right),token))
        both_waiting(scheduler,id)
        verify(cancellation_cancel(token));drive(scheduler,id)
        verify(task_status(scheduler,id)==TaskStatus.Cancelled && !task_timed_out(scheduler,id))
        verify(children_continued==0 && parent_continued==0)
        balanced();wait_closed(left);wait_closed(right)
    }
}
def timeout_checks(round:int) {
    reset()
    let left="silent_pair_timeout_left_{round}"
    let right="silent_pair_timeout_right_{round}"
    {
        var inscope scheduler <- task_scheduler(type<$Result<string;string>>)
        let id=task_spawn(scheduler,pair(left,right),TaskTimeout(after_ms=5))
        // Keep virtual time at zero until both connections are awaiting replies.
        both_waiting(scheduler,id);tick(scheduler,5l)
        verify(task_status(scheduler,id)==TaskStatus.Cancelled && task_timed_out(scheduler,id))
        verify(children_continued==0 && parent_continued==0)
        balanced();wait_closed(left);wait_closed(right)
    }
}
def first_error_checks(round:int) {
    reset()
    let left="pair_error_left_{round}"
    let right="silent_pair_error_right_{round}"
    {
        var inscope scheduler <- task_scheduler(type<$Result<string;string>>)
        // No timeout: only the first child's Error can close the waiting sibling.
        let id=task_spawn(scheduler,pair(left,right))
        drive(scheduler,id)
        verify(task_status(scheduler,id)==TaskStatus.Succeeded && !task_timed_out(scheduler,id))
        let result=task_value(scheduler,id)
        verify(result is err && result as err=="WebSocket: binary messages are unsupported by ws_receive_text")
        verify(fexist("{markers}/received_{right}"))
        verify(children_continued==0 && parent_continued==0)
        balanced();wait_closed(left);wait_closed(right)
    }
}
def checks(round:int) {
    success_checks(round);cancellation_checks(round);timeout_checks(round);first_error_checks(round)
    balanced()
}
[export]
def main() {
    port=to_int(get_env_variable("CE_HV_PORT"));markers=get_env_variable("CE_HV_MARKERS")
    started=ref_time_ticks()
    checks(0)
    let baseline=heap_bytes_allocated()
    for(round in range(1,4)) {checks(round);verify(heap_bytes_allocated()==baseline)}
    print("dasHV WebSocket and_bind checks OK\n")
}
