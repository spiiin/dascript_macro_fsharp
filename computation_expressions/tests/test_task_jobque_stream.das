options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require ../lib/task_jobque.das
require daslib/rtti
require daslib/fio
require strings

// Endless unless cancelled: proves cooperative cancellation reaches the worker.
def spin(limit:int;sink:TaskJobSink) : int {
    var n=0
    while(!task_job_cancelled(sink)) {
        n++
        if(limit>0 && n>=limit) {break}
        sleep(1u)
    }
    return n
}
def squares(n:int;sink:TaskJobSink) {
    for(i in range(n)) {
        if(!task_job_emit(sink,i*i)) {return}
    }
}
def chunks(n:int;sink:TaskJobSink) {
    for(i in range(n)) {
        var chunk:array<int>
        for(j in range(i+1)) {chunk |> push(j)}
        if(!task_job_emit(sink,chunk)) {return}
    }
}
def endless(unused:int;sink:TaskJobSink) {
    var i=0
    while(task_job_emit(sink,i)) {i++}
}
def broken(n:int;sink:TaskJobSink) {
    task_job_emit(sink,1)
    if(n>0) {panic("decoder failed")}
}

def drain_ints(var runtime:auto;stream:auto;var out:array<int>;var now:int&) : string {
    var error=""
    while(true) {
        var inscope next <- task_spawn(runtime,task_jobque_next(stream))
        for(i in range(200000)) {
            task_tick(runtime,now);now++
            if(task_status(next)!=TaskStatus.Waiting && task_status(next)!=TaskStatus.Created) {break}
        }
        verify(task_status(next)==TaskStatus.Succeeded)
        let value=task_value(next)
        if(value is err) {error=value as err;break}
        if(value as ok is none) {break}
        out |> push((value as ok) as some)
    }
    return error
}

def checks() {
    with_job_que() {
        var inscope queue <- task_job_queue()
        var inscope runtime <- task_runtime()
        var now=0
        {
            // Cancellable single job: finishes normally when not cancelled.
            var inscope done <- task_spawn(runtime,task_jobque_cancellable(queue,5,@@spin))
            for(i in range(200000)) {task_tick(runtime,now);now++;if(task_status(done)==TaskStatus.Succeeded) {break}}
            verify(task_value(done) is ok && task_value(done) as ok==5)
        }
        {
            // Timeout cancels the waiter and tells the endless worker to stop.
            var inscope endless_job <- task_spawn(runtime,task_jobque_cancellable(queue,0,@@spin),TaskTimeout(after_ms=10))
            for(i in range(20)) {task_tick(runtime,now);now++}
            verify(task_timed_out(runtime,endless_job))
            // The worker exits on its own; collect eventually removes its channel.
            for(i in range(200000)) {task_jobque_collect(queue);if(task_jobque_channels()==0) {break};sleep(1u)}
            verify(task_jobque_channels()==0)
        }
        {
            var inscope stream <- task_jobque_stream(queue,type<int>,5,@@squares,2)
            var values:array<int>
            verify(empty(drain_ints(runtime,stream,values,now)))
            verify(length(values)==5 && values[4]==16 && task_jobque_stream_done(stream))
            delete values
        }
        {
            // Owning payloads cross the thread boundary by clone.
            var inscope stream <- task_jobque_stream(queue,type<array<int>>,3,@@chunks)
            var total=0
            while(true) {
                var inscope next <- task_jobque_next(stream)
                for(i in range(200000)) {if(task_poll(next)!=TaskStatus.Waiting) {break}}
                var inscope value <- task_take(next)
                if(value as ok is none) {break}
                total+=length((value as ok) as some)
            }
            verify(total==6)
        }
        {
            // Worker panic arrives after the values emitted before it.
            var inscope stream <- task_jobque_stream(queue,type<int>,1,@@broken)
            var values:array<int>
            let error=drain_ints(runtime,stream,values,now)
            verify(length(values)==1 && find(error,"decoder failed")>=0)
            delete values
        }
        {
            // Cancelling an endless producer: backpressure keeps it bounded,
            // cancellation lets it exit, and next returns none afterwards.
            var inscope stream <- task_jobque_stream(queue,type<int>,0,@@endless,4)
            var inscope first <- task_jobque_next(stream)
            for(i in range(200000)) {if(task_poll(first)!=TaskStatus.Waiting) {break}}
            verify((first.value as ok) as some==0)
            task_jobque_stream_cancel(stream)
            var inscope after <- task_jobque_next(stream)
            verify(task_poll(after)==TaskStatus.Succeeded && (after.value as ok) is none)
        }
        {
            // Dropping a stream handle without reading also stops its worker.
            var inscope stream <- task_jobque_stream(queue,type<int>,0,@@endless,4)
            var inscope first <- task_jobque_next(stream)
            for(i in range(200000)) {if(task_poll(first)!=TaskStatus.Waiting) {break}}
        }
        for(i in range(200000)) {task_jobque_collect(queue);if(task_jobque_channels()==0) {break};sleep(1u)}
        verify(task_jobque_channels()==0)
    }
    verify(task_jobque_channels()==0)
}

[export]
def main() {
    checks();let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task jobque stream checks OK\n")
}
