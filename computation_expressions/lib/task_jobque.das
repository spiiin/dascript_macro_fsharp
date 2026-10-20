options gen2
module task_jobque public
require ./task_builder.das public
require daslib/jobque_boost public
require daslib/rtti

struct TaskJobQueueTag {_ce_marker:uint8}
var private native_channels=0

def task_jobque_channels() {return native_channels}
def private ce_jobque_remove(var record:auto) {
    if(record.channel!=null) {unsafe {channel_remove(record.channel)};native_channels--}
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
        var state=new tuple<references:uint64;closed:bool;records:array<tuple<channel:Channel?;waiting:bool>>>(references=uint64(1))
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
    if(op.index>=0) {op.state.records[op.index].waiting=false}
    op.state=null;sequence_close(op.lease);delete op
}}
def private ce_jobque_poll(var op:auto(O)?) {unsafe {
    typedef JobValue=typedecl(invoke(op.work,op.input)) -const -&
    if(!op.started) {
        if(op.state.closed) {panic("task jobque: queue is closed")}
        // Fail before allocating a native channel when the host has no pool.
        if(get_total_hw_jobs()<0) {panic("task jobque: invalid pool")}
        var ch=channel_create();append(ch,1)
        var record=length(op.state.records)
        for(i in range(length(op.state.records))) {if(op.state.records[i].channel==null) {record=i;break}}
        if(record==length(op.state.records)) {op.state.records |> push((channel=ch,waiting=true))}
        else {op.state.records[record]=(channel=ch,waiting=true)}
        native_channels++;op.index=record;op.started=true
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
    var inscope snapshot:tuple<value:Input -const -&>;snapshot.value := input
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
