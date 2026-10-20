options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require ../lib/task_channel.das
require ../lib/task_progress.das
require ../lib/task_jobque.das
require daslib/fio

// Application-level services: owning handles live outside CE generators.
var queue:typedecl(task_job_queue())
var loading:typedecl(task_progress(type<int>))
var decoded:typedecl(task_jobque_stream(task_job_queue(),type<int>,0,@@decode_chunks))
var input:typedecl(task_channel(type<string>,4))
var network:typedecl(task_channel(type<string>,4))

// Runs on a jobque worker: publishes decoded chunks, stops early when cancelled.
def decode_chunks(count:int;sink:TaskJobSink) {
    for(i in range(count)) {
        var checksum=0
        for(j in range((i+1)*2000)) {checksum+=j%7}
        if(!task_job_emit(sink,checksum)) {return}
    }
}
def load_level() {
    return <- computation(TaskResultBuilder(type<int>)) {
        var chunks=0
        while(true) {
            let chunk=task_jobque_next(decoded) |> bind
            if(chunk is none) {break}
            chunks++
            task_progress_report(loading,chunks*25)
        }
        task_progress_close(loading)
        return chunks
    }
}
def loading_screen() {
    return <- computation(TaskResultBuilder(type<int>)) {
        var shown=0
        while(true) {
            let percent=task_progress_wait(loading) |> bind
            if(percent is none) {break}
            shown=percent as some
        }
        return shown
    }
}
// Merges two event sources until both are closed.
def router() {
    return <- computation(TaskResultBuilder(type<string>)) {
        var log=""
        var open=2
        while(open>0) {
            let pick=task_channel_select(input,network) |> bind
            if(pick.value is none) {open--;continue}
            log+="{pick.index==0 ? "input" : "net"}={pick.value as some} "
        }
        return log
    }
}
def idle() {return <- task_from_poll(@(){return task_pending(type<int>)},@(){})}

[export]
def main() {
    with_job_que() {
        queue <- task_job_queue()
        loading <- task_progress(type<int>)
        decoded <- task_jobque_stream(queue,type<int>,4,@@decode_chunks,2)
        input <- task_channel(type<string>,4)
        network <- task_channel(type<string>,4)
        var inscope session <- cancellation_token()
        var inscope level <- cancellation_child(session)
        var inscope runtime <- task_runtime(TaskSchedulerConfig(max_polls_per_tick=8,max_tick_usec=4000))
        var inscope load <- task_spawn_named(runtime,"load level",task_with_cancellation(load_level(),level),TaskTimeout(after_ms=10000))
        var inscope screen <- task_spawn_named(runtime,"loading screen",loading_screen())
        var inscope events <- task_spawn_named(runtime,"router",router())
        var inscope ambient <- task_spawn_named(runtime,"ambient",task_with_cancellation(idle(),level))
        task_channel_try_send(input,"jump")
        task_channel_try_send(network,"ping")
        for(now_ms in range(10000)) {
            task_tick(runtime,now_ms)
            task_jobque_collect(queue)
            if(now_ms==5) {task_channel_close(input);task_channel_close(network)}
            if(task_status(load)==TaskStatus.Succeeded && task_status(screen)==TaskStatus.Succeeded && task_status(events)==TaskStatus.Succeeded) {break}
            sleep(1u) // Demo event loop; a game ticks once per frame.
        }
        verify(task_value(load) as ok==4 && task_value(screen) as ok==100)
        verify(task_value(events) as ok=="input=jump net=ping ")
        print(task_dump_text(runtime))
        // Leaving the level cancels its remaining work with a reason.
        cancellation_cancel(level,"level exit")
        task_tick(runtime,task_scheduler_time(runtime)+1)
        verify(task_status(ambient)==TaskStatus.Cancelled && cancellation_reason(level)=="level exit")
        verify(!cancellation_requested(session) && task_next_deadline(runtime)==-1l)
        delete runtime
        delete decoded
        for(i in range(10000)) {task_jobque_collect(queue);if(task_jobque_channels()==0) {break};sleep(1u)}
        delete input
        delete network
        delete loading
        delete queue
    }
    verify(task_jobque_channels()==0)
    print("Task toolkit demo OK\n")
}
