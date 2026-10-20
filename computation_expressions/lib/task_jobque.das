options gen2
module task_jobque public
require ./task_builder.das public
require daslib/jobque_boost public
require daslib/rtti
require daslib/fio

struct TaskJobQueueTag {_ce_marker:uint8}
struct TaskJobStreamTag {_ce_marker:uint8}
// Worker-side view of a cancellable job or stream. Valid only inside the job.
struct TaskJobSink {
    ch:Channel?
    cancel:Atomic32?
    pending:Atomic32?
    capacity:int
}
var private native_channels=0

def task_jobque_channels() {return native_channels}
def private ce_jobque_remove(var record:auto) {
    if(record.channel!=null) {unsafe {channel_remove(record.channel)};native_channels--}
    unsafe {
        if(record.cancel!=null) {atomic32_remove(record.cancel)}
        if(record.pending!=null) {atomic32_remove(record.pending)}
    }
}
def private ce_jobque_request_cancel(var record:auto) {
    if(record.cancel!=null) {record.cancel |> set(1)}
}
def private ce_jobque_lease(var state:auto(S)?;owner:bool=false) {
    return <- generator<S?> capture(copy(state),copy(owner)) {
        while(true) {yield state}
        return false
    } finally {ce_sequence_finalize($ {unsafe {
        if(owner) {state.closed=true}
        state.references--
        if(state.references==uint64(0)) {
            // The last lease is the shutdown join boundary. Keep the queue owner
            // alive in the event loop so cancelling a waiter cannot be the last lease.
            // Ask cooperative workers to stop before joining them.
            for(record in state.records) {if(record.channel!=null) {ce_jobque_request_cancel(record)}}
            for(record in state.records) {if(record.channel!=null) {join(record.channel);ce_jobque_remove(record)}}
            delete state
        }
    }})}
}
def private ce_jobque_state(queue:tuple<tag:TaskJobQueueTag;owner:iterator<auto(S)?>>) : S? {
    unsafe {
        var lease=reinterpret<iterator<S?>?>(addr(queue.owner));var state:S?
        if(!next(*lease,state)) {panic("task jobque: queue was moved or deleted")}
        return state
    }
}
def task_job_queue() {
    unsafe {
        var state=new tuple<references:uint64;closed:bool;records:array<tuple<channel:Channel?;waiting:bool;cancel:Atomic32?;pending:Atomic32?>>>(references=uint64(1))
        return <- (tag=TaskJobQueueTag(),owner <- ce_jobque_lease(state,true))
    }
}
def task_jobque_collect(queue:tuple<tag:TaskJobQueueTag;owner:iterator<auto(S)?>>) {
    var state=ce_jobque_state(queue);var removed=0
    unsafe {for(record in state.records) {
        if(record.channel!=null && !record.waiting && record.channel.isReady) {ce_jobque_remove(record);removed++}
    }}
    return removed
}
def private ce_jobque_finish(var op:auto(O)?) {unsafe {
    if(op.index>=0) {
        // Harmless after completion; stops a cooperative worker on cancel/timeout.
        ce_jobque_request_cancel(op.state.records[op.index])
        op.state.records[op.index].waiting=false
    }
    op.state=null;sequence_close(op.lease);delete op
}}
// Allocates a channel record (and optional atomics) for one native job.
def private ce_jobque_allocate(var state:auto(S)?;cooperative:bool) : int {unsafe {
    if(state.closed) {panic("task jobque: queue is closed")}
    if(get_total_hw_jobs()<0) {panic("task jobque: invalid pool")}
    var ch=channel_create();append(ch,1)
    var cancel:Atomic32?;var pending:Atomic32?
    if(cooperative) {cancel=atomic32_create();pending=atomic32_create()}
    var record=length(state.records)
    for(i in range(length(state.records))) {if(state.records[i].channel==null) {record=i;break}}
    if(record==length(state.records)) {state.records |> push((channel=ch,waiting=true,cancel=cancel,pending=pending))}
    else {state.records[record]=(channel=ch,waiting=true,cancel=cancel,pending=pending)}
    native_channels++
    return record
}}
def private ce_jobque_poll(var op:auto(O)?) {unsafe {
    typedef JobValue=typedecl(invoke(op.work,op.input)) -const -&
    if(!op.started) {
        // Fails before allocating a native channel when the host has no pool.
        let record=ce_jobque_allocate(op.state,false)
        var ch=op.state.records[record].channel
        op.index=record;op.started=true
        let work=op.work
        var inscope input_owner <- (value <- op.input)
        new_job() @() {
            var inscope outcome:$Result<JobValue;string>
            try {
                var inscope value_owner:tuple<value:JobValue>
                static_if(typeinfo can_copy(type<JobValue>)) {value_owner.value=invoke(work,input_owner.value)}
                else {value_owner.value <- invoke(work,input_owner.value)}
                outcome <- move_ok(value_owner.value)
            } recover {outcome <- move_error("{this_context().last_exception}",type<JobValue>)}
            var inscope packet <- (result <- outcome)
            ch |> push_clone(packet)
            ch |> notify_and_release
        }
    }
    var result:$Result<JobValue;string>
    var ch=op.state.records[op.index].channel
    let ready=try_pop_clone(ch,$(packet:tuple<result:$Result<JobValue;string>>#) {result := packet.result})
    if(ready) {return <- task_ready_move(result)}
    return <- task_pending(type<$Result<JobValue;string>>)
}}
// Work is a function pointer, not a closure borrowing main-thread state.
// The SDK clones input/result across contexts; no cooperative channel is shared.
def task_jobque_move(queue:tuple<tag:TaskJobQueueTag;owner:iterator<auto(S)?>>;
    var input:auto(Input);work:function<(input:Input):auto(Value)>) {
    static_assert(typeinfo ce_resumable_payload(default<Input -const -&>))
    static_assert(typeinfo ce_resumable_payload(default<Value -const -&>))
    var state=ce_jobque_state(queue)
    unsafe {
        if(state.closed) {panic("task jobque: queue is closed")}
        state.references++
        var lease <- ce_jobque_lease(state)
        var op=new tuple<state:S?;lease:typedecl(lease);index:int;started:bool;input:Input -const -&;work:typedecl(work) -const -&>(state=state,lease <- lease,index=-1,input <- input,work=work)
        return <- task_from_poll(@(){return <- ce_jobque_poll(op)},@(){ce_jobque_finish(op)})
    }
}

// Copy/clone the submission snapshot; use task_jobque_move to transfer it.
def task_jobque(queue:tuple<tag:TaskJobQueueTag;owner:iterator<auto(S)?>>;
    input:auto(Input);work:function<(input:Input):auto(Value)>) {
    var inscope snapshot <- default<tuple<value:Input -const -&>>;snapshot.value := input
    return <- task_jobque_move(queue,snapshot.value,work)
}

def task_job_queue_clone(queue:tuple<tag:TaskJobQueueTag;owner:iterator<auto(S)?>>) {
    var state=ce_jobque_state(queue);unsafe {
        if(state.references==uint64(-1)) {panic("task jobque: references exhausted")}
        state.references++
        return <- (tag=TaskJobQueueTag(),owner <- ce_jobque_lease(state))
    }
}
def clone(var target:tuple<tag:TaskJobQueueTag;owner:iterator<auto(S)?>>;source:tuple<tag:TaskJobQueueTag;owner:iterator<S?>>) {
    var next <- task_job_queue_clone(source);delete target;target <- next
}

// ---- Cooperative worker API -------------------------------------------------
// True once the waiting Task was cancelled, timed out or dropped, or the queue
// is shutting down. Long workers should check it and return early.
def task_job_cancelled(sink:TaskJobSink) : bool {
    if(sink.cancel==null) {return false}
    return (sink.cancel |> get)!=0
}
// Stream workers publish values with backpressure: while `capacity` values are
// unread the worker sleeps 1 ms between checks. Returns false (value dropped)
// once cancelled. The value type must match the stream's element type exactly.
def task_job_emit(sink:TaskJobSink;value:auto(T)) : bool {
    if(sink.ch==null || sink.pending==null) {panic("task_job_emit: sink is not a stream")}
    while(sink.capacity>0 && (sink.pending |> get)>=sink.capacity) {
        if(task_job_cancelled(sink)) {return false}
        sleep(1u)
    }
    if(task_job_cancelled(sink)) {return false}
    sink.pending |> inc
    var inscope packet:tuple<error:string;item:T -const -&>
    packet.item := value
    sink.ch |> push_clone(packet)
    return true
}

// ---- Cancellable single-result job ------------------------------------------
def private ce_jobque_poll_sink(var op:auto(O)?) {unsafe {
    typedef JobValue=typedecl(invoke(op.work,op.input,default<TaskJobSink>)) -const -&
    if(!op.started) {
        let record=ce_jobque_allocate(op.state,true)
        var ch=op.state.records[record].channel
        var cancel=op.state.records[record].cancel
        op.index=record;op.started=true
        let work=op.work
        var inscope input_owner <- (value <- op.input)
        new_job() @() {
            var inscope outcome:$Result<JobValue;string>
            try {
                let sink=TaskJobSink(cancel=cancel)
                var inscope value_owner:tuple<value:JobValue>
                static_if(typeinfo can_copy(type<JobValue>)) {value_owner.value=invoke(work,input_owner.value,sink)}
                else {value_owner.value <- invoke(work,input_owner.value,sink)}
                outcome <- move_ok(value_owner.value)
            } recover {outcome <- move_error("{this_context().last_exception}",type<JobValue>)}
            var inscope packet <- (result <- outcome)
            ch |> push_clone(packet)
            ch |> notify_and_release
        }
    }
    var result:$Result<JobValue;string>
    var ch=op.state.records[op.index].channel
    let ready=try_pop_clone(ch,$(packet:tuple<result:$Result<JobValue;string>>#) {result := packet.result})
    if(ready) {return <- task_ready_move(result)}
    return <- task_pending(type<$Result<JobValue;string>>)
}}
// Like task_jobque, but work also receives a TaskJobSink: cancelling or timing out
// the Task (or queue shutdown) makes task_job_cancelled(sink) true in the worker.
def task_jobque_cancellable(queue:tuple<tag:TaskJobQueueTag;owner:iterator<auto(S)?>>;
    input:auto(Input);work:function<(input:Input;sink:TaskJobSink):auto(Value)>) {
    static_assert(typeinfo ce_resumable_payload(default<Input -const -&>))
    static_assert(typeinfo ce_resumable_payload(default<Value -const -&>))
    var state=ce_jobque_state(queue)
    unsafe {
        if(state.closed) {panic("task jobque: queue is closed")}
        state.references++
        var lease <- ce_jobque_lease(state)
        var inscope snapshot <- default<tuple<value:Input -const -&>>;snapshot.value := input
        var op=new tuple<state:S?;lease:typedecl(lease);index:int;started:bool;input:Input -const -&;work:typedecl(work) -const -&>(state=state,lease <- lease,index=-1,input <- snapshot.value,work=work)
        return <- task_from_poll(@(){return <- ce_jobque_poll_sink(op)},@(){ce_jobque_finish(op)})
    }
}

// ---- Stream of values from one worker ---------------------------------------
def private ce_jobque_stream_stop(var op:auto(O)?) {unsafe {
    if(op.stopped) {return}
    op.stopped=true
    if(op.index>=0) {
        ce_jobque_request_cancel(op.state.records[op.index])
        op.state.records[op.index].waiting=false
        op.index=-1
    }
}}
def private ce_jobque_stream_lease(var op:auto(O)?;owner:bool=false) {
    return <- generator<O?> capture(copy(op),copy(owner)) {
        while(true) {yield op}
        return false
    } finally {ce_sequence_finalize($ {unsafe {
        if(owner) {ce_jobque_stream_stop(op)}
        op.references--
        if(op.references==uint64(0)) {
            ce_jobque_stream_stop(op)
            op.state=null;sequence_close(op.lease);delete op
        }
    }})}
}
def private ce_jobque_stream_op(stream:tuple<tag:TaskJobStreamTag;owner:iterator<auto(O)?>>) : O? {
    unsafe {
        var lease=reinterpret<iterator<O?>?>(addr(stream.owner));var op:O?
        if(!next(*lease,op)) {panic("task jobque stream: handle was moved or deleted")}
        return op
    }
}
def private ce_jobque_stream_start(var op:auto(O)?) {unsafe {
    typedef Item=typedecl(op.witness) -const -&
    let record=ce_jobque_allocate(op.state,true)
    var ch=op.state.records[record].channel
    var cancel=op.state.records[record].cancel
    var pending=op.state.records[record].pending
    op.index=record;op.started=true
    let work=op.work
    let capacity=op.capacity
    var inscope input_owner <- (value <- op.input)
    new_job() @() {
        try {
            let sink=TaskJobSink(ch=ch,cancel=cancel,pending=pending,capacity=capacity)
            invoke(work,input_owner.value,sink)
        } recover {
            var inscope packet:tuple<error:string;item:Item>
            packet.error="{this_context().last_exception}"
            if(empty(packet.error)) {packet.error="task jobque stream: worker failed"}
            ch |> push_clone(packet)
        }
        ch |> notify_and_release
    }
}}
def private ce_jobque_stream_pop(var op:auto(O)?;var result:auto&) : bool {unsafe {
    typedef Item=typedecl(op.witness) -const -&
    var ch=op.state.records[op.index].channel
    var error="";var got=false
    var item:Item
    let ready=try_pop_clone(ch,$(packet:tuple<error:string;item:Item>#) {
        got=true
        if(empty(packet.error)) {item := packet.item} else {error=string(packet.error)}
    })
    if(!ready || !got) {return false}
    if(!empty(error)) {
        op.failure=error
        ce_jobque_stream_stop(op)
        result <- move_error(error,type<$Option<Item>>)
        return true
    }
    op.state.records[op.index].pending |> dec
    var some_item <- ce_move_some(item)
    result <- move_ok(some_item)
    return true
}}
def private ce_jobque_next_poll(var op:auto(O)?) {unsafe {
    typedef Item=typedecl(op.witness) -const -&
    var result:$Result<$Option<Item>;string>
    if(!empty(op.failure)) {result <- move_error(op.failure,type<$Option<Item>>);return <- task_ready_move(result)}
    if(op.stopped) {var nothing=none(type<Item>);result <- move_ok(nothing);return <- task_ready_move(result)}
    if(!op.started) {ce_jobque_stream_start(op)}
    if(ce_jobque_stream_pop(op,result)) {return <- task_ready_move(result)}
    // The worker releases the channel only after its last push, so a second pop
    // after observing isReady cannot miss a value.
    if(op.state.records[op.index].channel.isReady) {
        if(ce_jobque_stream_pop(op,result)) {return <- task_ready_move(result)}
        op.done=true
        ce_jobque_stream_stop(op)
        var nothing=none(type<Item>);result <- move_ok(nothing)
        return <- task_ready_move(result)
    }
    return <- task_pending(type<$Result<$Option<Item>;string>>)
}}
// Cold stream: the worker starts on the first task_jobque_next poll. work(input,sink)
// publishes values with task_job_emit(sink,value) and checks task_job_cancelled.
// At most `capacity` values wait unread (0 = unbounded).
def task_jobque_stream(queue:tuple<tag:TaskJobQueueTag;owner:iterator<auto(S)?>>;unused:type<auto(T)>;
    input:auto(Input);work:function<(input:Input;sink:TaskJobSink):void>;capacity:int=64) {
    static_assert(typeinfo ce_resumable_payload(default<Input -const -&>))
    static_assert(typeinfo ce_resumable_payload(default<T -const -&>))
    if(capacity<0) {panic("task jobque stream: capacity must be non-negative")}
    var state=ce_jobque_state(queue)
    unsafe {
        if(state.closed) {panic("task jobque: queue is closed")}
        state.references++
        var lease <- ce_jobque_lease(state)
        var inscope snapshot <- default<tuple<value:Input -const -&>>;snapshot.value := input
        var op=new tuple<state:S?;lease:typedecl(lease);references:uint64;index:int;started:bool;stopped:bool;done:bool;failure:string;capacity:int;input:Input -const -&;work:typedecl(work) -const -&;witness:T -const -&>(state=state,lease <- lease,references=uint64(1),index=-1,capacity=capacity,input <- snapshot.value,work=work)
        return <- (tag=TaskJobStreamTag(),owner <- ce_jobque_stream_lease(op,true))
    }
}
// Task<Result<Option<T>,string>>: the next value, none after the worker returned
// (or after the stream was cancelled), err if the worker panicked.
def task_jobque_next(stream:tuple<tag:TaskJobStreamTag;owner:iterator<auto(O)?>>) {
    var op=ce_jobque_stream_op(stream)
    unsafe {
        if(op.references==uint64(-1)) {panic("task jobque stream: references exhausted")}
        op.references++
        var lease <- ce_jobque_stream_lease(op)
        var holder=new tuple<op:O?;lease:typedecl(lease)>(op=op,lease <- lease)
        return <- task_from_poll(@(){return <- ce_jobque_next_poll(holder.op)},@(){holder.op=null;delete holder.lease;delete holder})
    }
}
// Requests worker cancellation; later task_jobque_next calls return none.
def task_jobque_stream_cancel(stream:tuple<tag:TaskJobStreamTag;owner:iterator<auto(O)?>>) {
    var op=ce_jobque_stream_op(stream);ce_jobque_stream_stop(op)
}
def task_jobque_stream_done(stream:tuple<tag:TaskJobStreamTag;owner:iterator<auto(O)?>>) : bool {
    var op=ce_jobque_stream_op(stream);unsafe {return op.done}
}
def ce_dispose(var stream:tuple<tag:TaskJobStreamTag;owner:iterator<auto?>>) {sequence_close(stream.owner)}
