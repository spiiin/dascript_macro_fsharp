options gen2
options max_infer_passes=1024
require ../lib/reactivex_async_sequence.das
require ../../computation_expressions/lib/computation_macro.das
var actions:typedecl(rx_subject(type<int>))
var producerClosed=0

def actions_until_three() {
    return <- computation(AsyncSequenceBuilder()) {
        for(n in rx_clone(actions) |> rx_to_async_sequence(rx_queue(3,RxOverflowPolicy.drop_oldest))) {
            let value=task_after_polls(0,n) |> bind
            if(value==3) {break} // For closes the Rx subscription here.
            yield value
        }
    }
}
def consume_actions() {
    return <- computation(TaskBuilder(type<int>)) {
        var stream & = actions_until_three() |> use_resource
        var total=0
        while(true) {
            let item=async_sequence_next(stream) |> bind
            if(item is none) {break}
            total+=item as some
        }
        return total
    }
}
def readings() {
    return <- computation(AsyncSequenceBuilder()) {
        try_finally($ {
            for(n in range(1,4)) {
                task_delay_ms(2) |> bind
                yield n*10
            }
        },$ {producerClosed++})
    }
}
[export]
def main() {
    actions <- rx_subject(type<int>)
    var consumer <- consume_actions()
    verify(task_poll(consumer)==TaskStatus.Waiting && rx_subscriber_count(actions)==1)
    rx_subject_next(actions,1);rx_subject_next(actions,2);rx_subject_next(actions,3)
    verify(task_poll(consumer)==TaskStatus.Succeeded && task_value(consumer)==3)
    verify(rx_subscriber_count(actions)==0)
    print("Observable -> AsyncSequence, break: total {task_value(consumer)}\n")
    delete consumer;delete actions

    var inscope clock <- rx_virtual_scheduler()
    var source <- @() {return <- readings()} |> rx_from_async_sequence(clock) |> rx_take(2)
    var inscope sub <- rx_subscribe(source,@(n:int) {print("AsyncSequence -> Observable: {n}\n")},@(s:string) {panic(s)},@() {print("done\n")})
    delete source
    rx_advance_to(clock,20)
    verify(producerClosed==1 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)

    // Rx buffers are borrowed during a callback. The adapter snapshots each
    // array so the AsyncSequence consumer owns it after that callback returns.
    var inscope batches <- rx_range(1,6) |> rx_buffer(2) |> rx_to_async_sequence(2,RxOverflowPolicy.drop_oldest)
    while(true) {
        var request <- async_sequence_next(batches)
        verify(task_poll(request)==TaskStatus.Succeeded)
        var item <- task_take(request)
        if(item is none) {delete item;break}
        print("owning batch: {(item as some)[0]}, {(item as some)[1]}\n")
        delete item
    }
    print("ReactiveX AsyncSequence adapters demo OK\n")
}
