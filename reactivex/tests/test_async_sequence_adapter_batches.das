options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex_async_sequence.das
require ../../computation_expressions/lib/computation_macro.das
require daslib/rtti
var input:typedecl(rx_subject(type<int>))
var trace=""
def for_consumer(fail:bool) {
    return <- computation(AsyncSequenceBuilder()) {
        for(n in rx_clone(input) |> rx_to_async_sequence(2)) {
            let value=task_after_polls(0,n) |> bind
            if(fail) {panic("For body failed")}
            if(value==2) {break}
            yield value
        }
        // The inner subscription is already closed, even while the outer
        // stream suspends again after its For has broken.
        task_after_polls(1,0) |> bind
    }
}
def batch_consumer() {
    return <- computation(TaskBuilder(type<int>)) {
        var stream & = rx_clone(input) |> rx_buffer(2) |> rx_to_async_sequence(2) |> use_resource
        var item & = async_sequence_next(stream) |> bind
        verify(item is some && length(item as some)==2)
        task_after_polls(1,0) |> bind
        return (item as some)[0]+(item as some)[1]
    }
}
def checks() {
    for(policyId in range(3)) {
        let policy=policyId==0 ? RxOverflowPolicy.error : (policyId==1 ? RxOverflowPolicy.drop_oldest : RxOverflowPolicy.drop_latest)
        trace=""
        var stream <- rx_range(1,6) |> rx_buffer(2) |> rx_to_async_sequence(rx_queue(2,policy))
        var request <- async_sequence_next(stream)
        if(policyId==0) {verify(task_poll(request)==TaskStatus.Failed);delete request}
        else {
            verify(task_poll(request)==TaskStatus.Succeeded)
            var value <- task_take(request)
            verify(value is some && length(value as some)==2)
            trace+="{(value as some)[0]},{(value as some)[1]};";delete value
            var second <- async_sequence_next(stream);verify(task_poll(second)==TaskStatus.Succeeded)
            var next <- task_take(second)
            trace+="{(next as some)[0]},{(next as some)[1]};";delete next
            verify(trace==(policyId==1 ? "3,4;5,6;" : "1,2;3,4;"))
            var done <- async_sequence_next(stream);verify(task_poll(done)==TaskStatus.Succeeded && done.value is none);delete done
        }
        delete stream
    }
    // Closing a stream frees queued batches while its delivered next-Task
    // retains an independent owning packet until the consumer releases it.
    {
        var stream <- rx_range(1,3) |> rx_buffer(2) |> rx_to_async_sequence(2)
        var request <- async_sequence_next(stream)
        verify(task_poll(request)==TaskStatus.Succeeded && request.value is some)
        async_sequence_close(stream);delete stream
        verify(length(request.value as some)==2 && (request.value as some)[0]==1 && (request.value as some)[1]==2)
        var value <- task_take(request)
        verify((value as some)[1]==2);delete value
    }
    for(mode in range(3)) {
        input <- rx_subject(type<int>)
        var stream <- rx_clone(input) |> rx_buffer(2) |> rx_to_async_sequence(2)
        var request <- async_sequence_next(stream)
        verify(task_poll(request)==TaskStatus.Waiting)
        for(n in range(1,5)) {rx_subject_next(input,n)}
        if(mode==0) {task_cancel(request);verify(task_status(request)==TaskStatus.Cancelled)}
        elif(mode==1) {
            rx_subject_error(input,"source failed")
            verify(rx_subscriber_count(input)==0 && task_poll(request)==TaskStatus.Failed)
        } else {
            delete stream
            verify(task_poll(request)==TaskStatus.Cancelled)
        }
        delete request;delete stream
        verify(rx_subscriber_count(input)==0);delete input
    }
    // A move-only batch borrowed through pipe bind stays alive over another
    // suspension; cancellation frees both that frame and newer queued batches.
    for(mode in range(2)) {
        input <- rx_subject(type<int>)
        var job <- batch_consumer()
        verify(task_poll(job)==TaskStatus.Waiting)
        rx_subject_next(input,1);rx_subject_next(input,2)
        verify(task_poll(job)==TaskStatus.Waiting)
        rx_subject_next(input,3);rx_subject_next(input,4)
        if(mode==0) {verify(task_poll(job)==TaskStatus.Succeeded && task_value(job)==3)}
        else {task_cancel(job);verify(task_status(job)==TaskStatus.Cancelled)}
        delete job;verify(rx_subscriber_count(input)==0);delete input
    }
    // Native asynchronous For consumes the adapter with the usual pipe bind.
    // Breaking or failing its body closes the underlying Rx subscription.
    for(mode in range(2)) {
        input <- rx_subject(type<int>)
        var stream <- for_consumer(mode==1)
        var request <- async_sequence_next(stream)
        verify(task_poll(request)==TaskStatus.Waiting && rx_subscriber_count(input)==1)
        rx_subject_next(input,1);rx_subject_next(input,2)
        verify(task_poll(request)==(mode==1 ? TaskStatus.Failed : TaskStatus.Succeeded))
        delete request
        if(mode==0) {
            var done <- async_sequence_next(stream)
            verify(task_poll(done)==TaskStatus.Waiting && rx_subscriber_count(input)==0)
            verify(task_poll(done)==TaskStatus.Succeeded && done.value is none)
            delete done
        }
        verify(rx_subscriber_count(input)==0)
        delete stream;delete input
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX AsyncSequence batch adapter checks OK\n")
}
