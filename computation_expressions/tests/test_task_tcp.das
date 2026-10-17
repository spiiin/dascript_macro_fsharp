options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require ../lib/task_tcp.das
require daslib/fio
require daslib/strings_convert
require daslib/rtti
require daslib/jobque_boost
var port=0
var continued=0
def request(command:string) {
    return <- computation(TaskResultBuilder(type<string>)) {
        let line=task_tcp_request_line("127.0.0.1",port,command) |> bind
        continued++
        return line
    }
}
[export]
def main() {
    port=to_int(get_env_variable("CE_TASK_TCP_PORT"))
    verify(port>0)
    var inscope scheduler <- task_scheduler(type<variant<ok:string;error:string>>)
    let start=ref_time_ticks()
    let success=task_spawn(scheduler,request("ok\n"))
    while(task_status(scheduler,success)==TaskStatus.Created || task_status(scheduler,success)==TaskStatus.Waiting) {
        let now=int64(get_time_usec(start)/1000)
        verify(now<5000l)
        task_tick(scheduler,now)
        sleep(1u)
    }
    let value=task_value(scheduler,success)
    print("TCP outcome={value}, continued={continued}\n")
    verify(value is ok && value as ok=="hello" && continued==1)
    verify(task_tcp_stats().active==0)
    var inscope token <- cancellation_token()
    let cancelled=task_spawn(scheduler,task_with_cancellation(request("wait\n"),token))
    task_tick(scheduler,int64(get_time_usec(start)/1000))
    verify(task_status(scheduler,cancelled)==TaskStatus.Waiting && task_tcp_stats().active==1)
    cancellation_cancel(token)
    task_tick(scheduler,int64(get_time_usec(start)/1000))
    verify(task_status(scheduler,cancelled)==TaskStatus.Cancelled && task_tcp_stats().active==0 && continued==1)
    let timed=task_spawn(scheduler,request("wait\n"),TaskTimeout(after_ms=30))
    while(task_status(scheduler,timed)==TaskStatus.Created || task_status(scheduler,timed)==TaskStatus.Waiting) {
        let now=int64(get_time_usec(start)/1000)
        verify(now<5000l)
        task_tick(scheduler,now)
        sleep(1u)
    }
    verify(task_status(scheduler,timed)==TaskStatus.Cancelled && task_timed_out(scheduler,timed))
    verify(task_tcp_stats().active==0 && continued==1)
    let eof=task_spawn(scheduler,request("eof\n"))
    while(task_status(scheduler,eof)==TaskStatus.Created || task_status(scheduler,eof)==TaskStatus.Waiting) {
        let now=int64(get_time_usec(start)/1000);verify(now<5000l)
        task_tick(scheduler,now);sleep(1u)
    }
    let error=task_value(scheduler,eof)
    verify(error is error && continued==1 && task_tcp_stats().active==0)
    task_scheduler_close(scheduler)
    let stats=task_tcp_stats()
    verify(stats.created==4 && stats.released==4)
    print("Task TCP network checks OK\n")
}
