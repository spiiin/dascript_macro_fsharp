options gen2
module reactivex_async_sequence public
require ./reactivex_task.das public
require ../../computation_expressions/lib/async_sequence_builder.das public

// Counted callback leases outlive removal of their subscription/timer. The
// producer and its current delivery frame remain valid during reentrant close.
def private rx_stream_finalize(action:block<():void>) {try {panic("__rx_stream_finalize")} recover {invoke(action)}}
def private rx_stream_lease(var state:auto(S)?) {
    return <- generator<S?> capture(copy(state)) {
        while(true) {yield state}
        return false
    } finally {rx_stream_finalize($ {unsafe {state.references--;if(state.references==0) {delete state}}})}
}
def private rx_stream_node(var data:auto) {
    var state=new tuple<references:int;data:typedecl(data) -const -&>(references=1,data <- data)
    unsafe {return <- typeinfo rx_normalized((owner <- rx_stream_lease(state)))}
}
def private rx_stream_state(handle:tuple<owner:iterator<auto(S)?>>) : S? {
    if(empty(handle.owner)) {panic("rx async sequence: adapter was moved or deleted")}
    unsafe {
        var lease=reinterpret<iterator<S?>?>(addr(handle.owner))
        var state:S?
        if(!next(*lease,state)) {panic("rx async sequence: invalid adapter lease")}
        return state
    }
}
def private rx_stream_ref(handle:tuple<owner:iterator<auto?>>) {
    var state=rx_stream_state(handle)
    unsafe {state.references++}
    return <- (owner <- rx_stream_lease(state))
}
def private rx_stream_delete(var value:auto) {static_if(typeinfo can_delete(value)) {delete value}}

def private rx_to_stream_close(op:auto) : void {
    unsafe {
        let state=rx_stream_state(op)
        if(state.data.closed) {return}
        state.data.closed=true
        var pending <- state.data.queue
        var failed=false;var message=""
        try {rx_unsubscribe(state.data.control)} recover {failed=true;message="{this_context().last_exception}"}
        try {delete pending} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        try {delete state.data.source} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        if(failed) {panic(message)}
    }
}
def private rx_to_stream_fail(op:auto;message:string) : void {
    unsafe {
        let state=rx_stream_state(op)
        if(state.data.failed || state.data.closed) {return}
        state.data.failed=true;state.data.done=true;state.data.error=clone_string(message)
        var pending <- state.data.queue
        // The stream error takes precedence over errors during upstream close.
        try {rx_unsubscribe(state.data.control)} recover {}
        try {delete pending} recover {}
    }
}
def private rx_to_stream_snapshot(var queue:array<auto(StreamItem)>;value:StreamItem) {
    static_if(typeinfo is_array(type<StreamItem>)) {
        var snapshot:StreamItem
        snapshot := value
        queue |> emplace(snapshot)
    } static_elif(typeinfo is_string(type<StreamItem>)) {queue |> push(clone_string(value))}
    else {queue |> push(value)}
}
def private rx_to_stream_accept(op:auto;value:auto) : void {
    unsafe {
        let state=rx_stream_state(op)
        if(state.data.done || state.data.closed) {return}
        if(length(state.data.queue)>=state.data.capacity) {
            if(state.data.policy==RxOverflowPolicy.error) {rx_to_stream_fail(op,"rx_to_async_sequence: queue overflow");return}
            if(state.data.policy==RxOverflowPolicy.drop_latest) {return}
            var removed <- state.data.queue[0];state.data.queue |> erase(0)
            // Commit the new snapshot before a finalizer can reenter. Later
            // arrivals may then evict it without exceeding the capacity.
            var failed=false;var message=""
            try {rx_to_stream_snapshot(state.data.queue,value)} recover {failed=true;message="{this_context().last_exception}"}
            try {rx_stream_delete(removed)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
            if(failed) {panic(message)}
        } else {rx_to_stream_snapshot(state.data.queue,value)}
    }
}
def private rx_to_stream_start(op:auto;marker:type<auto(StreamItem)>) : void {
    unsafe {
        let state=rx_stream_state(op)
        if(state.data.started) {return}
        state.data.started=true
        var values <- rx_stream_ref(op);var errors <- rx_stream_ref(op);var completed <- rx_stream_ref(op)
        var on_next <- @ capture(<-values) (value:StreamItem) {
            var failed=false;var message=""
            try {rx_to_stream_accept(values,value)} recover {failed=true;message="{this_context().last_exception}"}
            if(failed) {rx_to_stream_fail(values,message);panic(message)}
        } finally {rx_stream_finalize($ {delete values})}
        var on_error <- @ capture(<-errors) (message:string) {rx_to_stream_fail(errors,message)} finally {rx_stream_finalize($ {delete errors})}
        var on_complete <- @ capture(<-completed) () {unsafe {rx_stream_state(completed).data.done=true}} finally {rx_stream_finalize($ {delete completed})}
        rx_subscribe_with(state.data.control,state.data.source,on_next,on_error,on_complete)
    }
}
def private rx_to_stream_check_array(marker:type<array<auto(StreamItem)>>) {
    static_assert(typeinfo rx_payload(default<StreamItem>))
    concept_assert(typeinfo can_copy(type<StreamItem>),"rx_to_async_sequence: buffer batch elements must be copyable")
}

def rx_to_async_sequence(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(StreamItem)>>;queue_options:RxQueueOptions) {
    if(queue_options.capacity<=0) {panic("rx_to_async_sequence: queue capacity must be positive")}
    if(queue_options.policy!=RxOverflowPolicy.error && queue_options.policy!=RxOverflowPolicy.drop_oldest && queue_options.policy!=RxOverflowPolicy.drop_latest) {panic("rx_to_async_sequence: invalid overflow policy")}
    static_assert(typeinfo rx_payload(default<StreamItem>))
    static_if(typeinfo is_array(type<StreamItem>)) {rx_to_stream_check_array(type<StreamItem>)}
    else {concept_assert(typeinfo can_copy(type<StreamItem>),"rx_to_async_sequence: values must be copyable or buffer batches")}
    var queue:array<StreamItem>
    var op <- rx_stream_node((source <- source,control <- rx_subscription(),queue <- queue,
        capacity=queue_options.capacity,policy=queue_options.policy,started=false,closed=false,done=false,failed=false,error=""))
    var events <- generator<tuple<tag:TaskEventTag;ready:bool;value:variant<some:StreamItem;none:bool>>> capture(<-op) {
        rx_to_stream_start(op,type<StreamItem>)
        while(true) {
            unsafe {
                let state=rx_stream_state(op)
                if(state.data.failed) {panic(state.data.error)}
                if(!empty(state.data.queue)) {
                    var item:variant<some:StreamItem;none:bool>
                    item as some <- state.data.queue[0]
                    state.data.queue |> erase(0)
                    yield <- task_ready_move(item)
                } elif(state.data.done) {
                    var item <- move_none(type<StreamItem>)
                    yield <- task_ready_move(item)
                    return false
                } else {yield <- task_pending(type<variant<some:StreamItem;none:bool>>)}
            }
        }
        return false
    } finally {rx_stream_finalize($ {
        var failed=false;var message=""
        try {rx_to_stream_close(op)} recover {failed=true;message="{this_context().last_exception}"}
        delete op
        // A throwing native generator finalizer can skip its deallocation.
        // Report through the enclosing Task's cleanup scope after releasing it.
        if(failed) {ce_task_cleanup_error(message)}
    })}
    return <- ce_sequence_run(AsyncSequenceBuilder(type<StreamItem>),events)
}
def rx_to_async_sequence(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;capacity:int=32;policy:RxOverflowPolicy=RxOverflowPolicy.error) {
    return <- rx_to_async_sequence(source,rx_queue(capacity,policy))
}

def private rx_from_stream_dispose(op:auto) : void {
    unsafe {
        let state=rx_stream_state(op)
        if(state.data.disposed) {return}
        state.data.disposed=true
        var failed=false;var message=""
        if(state.data.has_request) {
            try {
                let cancelled=task_cancel(state.data.request)
                if(cancelled && task_status(state.data.request)==TaskStatus.Failed) {failed=true;message=clone_string(task_error(state.data.request))}
            } recover {failed=true;message="{this_context().last_exception}"}
            try {delete state.data.request} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
            state.data.has_request=false
        }
        try {ce_dispose(state.data.stream)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        if(failed) {panic(message)}
    }
}
def private rx_from_stream_stop(op:auto) : void {
    unsafe {
        let state=rx_stream_state(op)
        state.data.stopped=true
        var scheduled=state.data.scheduled;state.data.scheduled=RxScheduledId()
        var lifecycle=state.data.lifecycle;state.data.lifecycle=RxScheduledId()
        var failed=false;var message=""
        try {rx_cancel(state.data.clock,scheduled)} recover {failed=true;message="{this_context().last_exception}"}
        try {rx_cancel(state.data.clock,lifecycle)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        // Reentrant unsubscribe must never destroy an active producer frame.
        if(!state.data.polling) {
            try {rx_from_stream_dispose(op)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        }
        if(failed) {panic(message)}
    }
}
def private rx_from_stream_poll(op:auto) : void {
    unsafe {
        let state=rx_stream_state(op)
        if(state.data.stopped || rx_sink_stopped(state.data.sink)) {return}
        state.data.scheduled=RxScheduledId()
        state.data.polling=true
        var status=TaskStatus.Created;var failed=false;var message=""
        try {
            if(!state.data.has_request) {state.data.request <- async_sequence_next(state.data.stream);state.data.has_request=true}
            ce_task_clock_scope(state.data.clock_owner,rx_now_ms(state.data.clock),$ {status=task_poll(state.data.request)})
        } recover {failed=true;message="{this_context().last_exception}"}
        state.data.polling=false
        if(state.data.stopped || rx_sink_stopped(state.data.sink)) {rx_from_stream_dispose(op);return}
        if(failed) {rx_sink_error(state.data.sink,message);return}
        if(status==TaskStatus.Failed) {var error=clone_string(task_error(state.data.request));rx_sink_error(state.data.sink,error);return}
        if(status==TaskStatus.Cancelled) {rx_sink_error(state.data.sink,"rx async sequence cancelled");return}
        if(status==TaskStatus.Succeeded) {
            var item <- task_take(state.data.request)
            state.data.has_request=false
            try {
                if(item is none) {rx_sink_complete(state.data.sink)}
                else {rx_sink_next(state.data.sink,item as some)}
            } recover {failed=true;message="{this_context().last_exception}"}
            try {rx_stream_delete(item)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
            if(failed) {panic(message)}
        }
        if(!state.data.stopped && !rx_sink_stopped(state.data.sink)) {rx_from_stream_schedule(op,state.data.period)}
    }
}
def private rx_from_stream_schedule(op:auto;duration:int64) : void {
    unsafe {
        let state=rx_stream_state(op)
        if(state.data.stopped || rx_sink_stopped(state.data.sink)) {return}
        var owner <- rx_stream_ref(op);var closing <- rx_stream_ref(op)
        var action <- @ capture(<-owner) () {rx_from_stream_poll(owner)} finally {rx_stream_finalize($ {delete owner})}
        var on_close <- @ capture(<-closing) () {unsafe {rx_sink_error(rx_stream_state(closing).data.sink,"rx scheduler closed")}} finally {rx_stream_finalize($ {delete closing})}
        var failed=false;var message=""
        try {state.data.scheduled=rx_schedule(state.data.clock,duration,action,on_close)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {rx_sink_error(state.data.sink,message)}
    }
}
def private rx_from_stream_factory(var factory:auto;scheduler:RxScheduler;period:int64;marker:auto(Sink)) : lambda<(sink:Sink):void> {
    var clock <- rx_scheduler_clone(scheduler)
    return <- @ capture(<-factory,<-clock,copy(period)) (sink:Sink) {
        if(rx_scheduler_closed(clock)) {rx_sink_error(sink,"rx scheduler closed");return}
        var stream:typedecl(invoke(factory)) -const -&
        var failed=false;var message=""
        try {stream <- invoke(factory)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {delete stream;rx_sink_error(sink,message);return}
        if(rx_sink_stopped(sink)) {ce_dispose(stream);return}
        var request:typedecl(async_sequence_next(stream)) -const -&
        var op <- rx_stream_node((stream <- stream,request <- request,has_request=false,sink <- rx_sink_clone(sink),clock <- rx_scheduler_clone(clock),
            period=period,clock_owner=rx_adapter_clock_identity(),scheduled=RxScheduledId(),lifecycle=RxScheduledId(),polling=false,stopped=false,disposed=false))
        var owner <- rx_stream_ref(op)
        var cleanup <- @ capture(<-owner) () {rx_from_stream_stop(owner)} finally {rx_stream_finalize($ {delete owner})}
        try {
            rx_sink_add_cleanup(sink,cleanup)
            let state=rx_stream_state(op)
            if(!state.data.stopped && !rx_sink_stopped(sink)) {
                var closing <- rx_stream_ref(op)
                var on_close <- @ capture(<-closing) () {unsafe {rx_sink_error(rx_stream_state(closing).data.sink,"rx scheduler closed")}} finally {rx_stream_finalize($ {delete closing})}
                state.data.lifecycle=rx_on_scheduler_close(state.data.clock,on_close)
                rx_from_stream_schedule(op,0l)
            }
        } recover {failed=true;message="{this_context().last_exception}"}
        delete op
        if(failed) {panic(message)}
    } finally {rx_stream_finalize($ {unsafe {delete factory};delete clock})}
}
def private rx_from_stream_node(var factory:auto;scheduler:RxScheduler;period:int64;
    marker:tuple<tag:AsyncSequenceTag;owner:iterator<auto>;element:iterator<auto(StreamItem)>>) {
    var wrapper <- rx_from_stream_factory(factory,scheduler,period,rx_sink_marker(type<StreamItem>))
    return <- rx_create(type<StreamItem>,wrapper)
}
def rx_from_async_sequence(var factory:auto;scheduler:RxScheduler;poll_ms:int64=1l) {
    if(poll_ms<=0) {panic("rx_from_async_sequence: poll period must be positive")}
    return <- rx_from_stream_node(factory,scheduler,poll_ms,default<typedecl(invoke(factory))>)
}
def rx_from_async_sequence(var factory:auto;scheduler:RxScheduler;poll_ms:int) {return <- rx_from_async_sequence(factory,scheduler,int64(poll_ms))}
