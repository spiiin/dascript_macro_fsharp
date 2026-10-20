options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require ../lib/task_tcp.das
require daslib/fio
require daslib/strings_convert
require daslib/rtti
require daslib/jobque_boost
var port=0
def read_line(command:string) {
    return <- computation(TaskResultBuilder(type<string>)) {
        let value=task_tcp_request_line("127.0.0.1",port,command) |> bind
        return "Reply: {value}"
    }
}
def drive(var scheduler:auto;id:TaskId;started:int64) {
    while(task_status(scheduler,id)==TaskStatus.Created || task_status(scheduler,id)==TaskStatus.Waiting) {
        let ms=int64(get_time_usec(started)/1000)
        verify(ms<5000l)
        task_tick(scheduler,ms);sleep(1u)
    }
}
[export]
def main() {
    port=to_int(get_env_variable("CE_TASK_TCP_PORT"))
    var inscope scheduler <- task_scheduler(type<$Result<string;string>>)
    let started=ref_time_ticks()
    let good=task_spawn(scheduler,read_line("ok\n"))
    drive(scheduler,good,started)
    let reply=task_value(scheduler,good)
    verify(reply is ok && reply as ok=="Reply: hello")
    var inscope token <- cancellation_token()
    let cancelled=task_spawn(scheduler,task_with_cancellation(read_line("wait\n"),token))
    task_tick(scheduler,int64(get_time_usec(started)/1000))
    cancellation_cancel(token)
    drive(scheduler,cancelled,started)
    verify(task_status(scheduler,cancelled)==TaskStatus.Cancelled)
    let timed=task_spawn(scheduler,read_line("wait\n"),TaskTimeout(after_ms=30))
    drive(scheduler,timed,started)
    verify(task_timed_out(scheduler,timed))
    let eof=task_spawn(scheduler,read_line("eof\n"))
    drive(scheduler,eof,started)
    let error=task_value(scheduler,eof)
    verify(error is err && task_tcp_stats().active==0)
    print("Task TCP demo OK\n")
}
