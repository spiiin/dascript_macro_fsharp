options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require ../lib/task_events.das
require daslib/fio
require daslib/rtti
require daslib/jobque_boost
require daslib/strings_convert
require strings
require math

var input_lines:typedecl(task_event_source(type<string>))
var input_buffer=""
var input_eof=false
var quit_requested=false
var stop_background=false
var background_ticks=0

def log_line(text:string) {print("{text}\n");fflush(fstdout())}
def setting(name:string;fallback:int) {
    let value=get_env_variable(name)
    if(empty(value)) {return fallback}
    let parsed=to_int(value)
    if(parsed<1 || parsed>600000) {panic("{name}: expected an integer between 1 and 600000")}
    return parsed
}

// stdin must be a pipe, unbuffered and binary. Read only bytes known to be ready;
// fgets/ReadLine would block on partial input even after fpoll returned true.
// The one-shot console frontend closes the pipe after its line/command, so EOF
// also drains any CRT read-ahead bytes before the event source is closed.
def pump_keyboard(token:CancellationToken) {
    for(i in range(256)) {
        if(input_eof || !fpoll(fstdin(),0)) {break}
        var byte:uint8[1]
        let count=fread(fstdin(),byte)
        let ch=int(byte[0])
        if(count!=1) {
            input_eof=true
            task_event_close(input_lines)
            break
        }
        if(ch==10) {
            let line=input_buffer
            input_buffer=""
            if(line=="/cancel") {cancellation_cancel(token)}
            elif(line=="/quit") {cancellation_cancel(token);quit_requested=true;break}
            else {task_event_emit(input_lines,line)}
        } elif(ch!=13) {
            input_buffer+=to_char(ch)
            if(length(input_buffer)>4096) {
                log_line("INPUT_TOO_LONG")
                input_eof=true;input_buffer=""
                task_event_close(input_lines)
                break
            }
        }
    }
}

def read_user_input() {
    return <- computation(TaskResultBuilder(type<string>)) {
        let text=task_wait_event(input_lines) |> bind
        return text
    }
}
def background_work(interval_ms:int) {
    return <- computation(TaskResultBuilder(type<string>)) {
        while(!stop_background) {
            task_delay_ms(interval_ms) |> bind
            background_ticks++
            log_line("HEARTBEAT={background_ticks}")
        }
        return "background finished"
    }
}
def active(status:TaskStatus) {return status==TaskStatus.Created || status==TaskStatus.Waiting}

[export]
def main() {
    if(is_terminal(0)) {
        log_line("Run ./run_task_keyboard.ps1 for interactive input (stdin must be a pipe).")
        return
    }
    let timeout_ms=setting("CE_KEYBOARD_TIMEOUT_MS",15000)
    let interval_ms=setting("CE_KEYBOARD_HEARTBEAT_MS",500)
    let settle_ms=max(setting("CE_KEYBOARD_SETTLE_MS",interval_ms+100),interval_ms+30)
    funbuffered(fstdin());fbinary(fstdin())
    input_lines <- task_event_source(type<string>)
    var inscope token <- cancellation_token()
    var inscope scheduler <- task_scheduler(type<$Result<string;string>>)
    let reader=task_spawn(scheduler,task_with_cancellation(read_user_input(),token),TaskTimeout(after_ms=int64(timeout_ms)))
    let background=task_spawn(scheduler,background_work(interval_ms))
    let started=ref_time_ticks()
    verify(task_tick(scheduler,0)==2 && task_event_subscriber_count(input_lines)==1)
    log_line("READY timeout_ms={timeout_ms}")
    log_line("Enter text + Enter; Esc or /cancel cancels the wait; /quit stops the demo.")

    var terminal_at=-1l
    var ticks_at_terminal=0
    while(true) {
        let now_ms=int64(get_time_usec(started)/1000)
        pump_keyboard(token)
        task_tick(scheduler,now_ms)
        if(quit_requested) {log_line("QUIT");break}
        if(terminal_at<0 && !active(task_status(scheduler,reader))) {
            terminal_at=now_ms;ticks_at_terminal=background_ticks
            verify(task_event_subscriber_count(input_lines)==0)
            let status=task_status(scheduler,reader)
            if(status==TaskStatus.Cancelled) {
                log_line(task_timed_out(scheduler,reader) ? "TIMEOUT" : "CANCELLED")
            } elif(status==TaskStatus.Failed) {panic(task_error(scheduler,reader))}
            else {
                let result=task_value(scheduler,reader)
                if(result is ok) {log_line("INPUT={result as ok}")}
                else {log_line("ERROR={result as err}")}
            }
        }
        if(terminal_at>=0 && now_ms-terminal_at>=int64(settle_ms)) {
            verify(background_ticks>ticks_at_terminal)
            verify(active(task_status(scheduler,background)))
            log_line("BACKGROUND_AFTER_INPUT={background_ticks-ticks_at_terminal}")
            break
        }
        sleep(5u)
    }
    stop_background=true
    task_scheduler_close(scheduler)
    verify(task_status(scheduler,background)==TaskStatus.Cancelled)
    delete input_lines
    input_buffer=""
    let stats=task_event_stats()
    verify(stats.sources==0 && stats.waits==0 && stats.subscriptions==0)
    log_line("SUBSCRIPTIONS=0")
    log_line("Task keyboard demo OK")
}
