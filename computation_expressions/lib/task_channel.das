options gen2
module task_channel public
require ./task_builder.das public

struct TaskChannelTag {_ce_marker:uint8}

def private ce_channel_lease(var state:auto(S)?;owner:bool=false) {
    return <- generator<S?> capture(copy(state),copy(owner)) {
        while(true) {yield state}
        return false
    } finally {ce_sequence_finalize($ {unsafe {
        if(owner) {state.closed=true}
        state.references--
        if(state.references==uint64(0)) {delete state}
    }})}
}
def private ce_channel_state(channel:tuple<tag:TaskChannelTag;owner:iterator<auto(S)?>>) : S? {
    unsafe {
        var lease=reinterpret<iterator<S?>?>(addr(channel.owner));var state:S?
        if(!next(*lease,state)) {panic("task channel: handle was moved or deleted")}
        return state
    }
}
def task_channel(unused:type<auto(T)>;capacity:int) {
    static_assert(typeinfo ce_resumable_payload(default<T -const -&>))
    if(capacity<=0) {panic("task channel: capacity must be positive")}
    unsafe {
        var state=new tuple<references:uint64;closed:bool;error:string;capacity:int;serial:uint64;queue:array<T -const -&>;senders:array<uint64>;readers:array<uint64>>(references=uint64(1),capacity=capacity)
        return <- (tag=TaskChannelTag(),owner <- ce_channel_lease(state,true))
    }
}
def task_channel_clone(channel:tuple<tag:TaskChannelTag;owner:iterator<auto(S)?>>) {
    var state=ce_channel_state(channel)
    unsafe {
        if(state.references==uint64(-1)) {panic("task channel: references exhausted")}
        state.references++
        return <- (tag=TaskChannelTag(),owner <- ce_channel_lease(state))
    }
}
def task_channel_close(channel:tuple<tag:TaskChannelTag;owner:iterator<auto(S)?>>) {
    var state=ce_channel_state(channel);unsafe {state.closed=true}
}
def task_channel_fail(channel:tuple<tag:TaskChannelTag;owner:iterator<auto(S)?>>;message:string) {
    var state=ce_channel_state(channel);unsafe {
        if(!state.closed) {state.closed=true;state.error=empty(message) ? "channel failed" : message;delete state.queue}
    }
}
def task_channel_count(channel:tuple<tag:TaskChannelTag;owner:iterator<auto(S)?>>) {var state=ce_channel_state(channel);unsafe {return length(state.queue)}}
def task_channel_waiters(channel:tuple<tag:TaskChannelTag;owner:iterator<auto(S)?>>) {var state=ce_channel_state(channel);unsafe {return length(state.senders)+length(state.readers)}}
def ce_dispose(var channel:tuple<tag:TaskChannelTag;owner:iterator<auto?>>) {sequence_close(channel.owner)}

def private ce_channel_remove(var list:array<uint64>;id:uint64) {for(i in range(length(list))) {if(list[i]==id) {list |> erase(i);break}}}
def private ce_channel_register(var state:auto(S)?;sender:bool) : uint64 {unsafe {
    if(state.serial==uint64(-1)) {panic("task channel: waiter identities exhausted")}
    state.serial++
    if(sender) {state.senders |> push(state.serial)} else {state.readers |> push(state.serial)}
    return state.serial
}}
def task_channel_try_send_move(channel:tuple<tag:TaskChannelTag;owner:iterator<auto(S)?>>;var value:auto) : bool {
    var state=ce_channel_state(channel);unsafe {
        if(state.closed || !empty(state.senders) || length(state.queue)>=state.capacity) {return false}
        state.queue |> emplace(value);return true
    }
}
def task_channel_try_send(channel:tuple<tag:TaskChannelTag;owner:iterator<auto(S)?>>;value:auto(T)) {
    concept_assert(typeinfo can_copy(type<T>),"task channel: use task_channel_send_move for an owning payload")
    static_if(typeinfo is_string(type<T>)) {var item=string(value);return task_channel_try_send_move(channel,item)}
    else {var item=value;return task_channel_try_send_move(channel,item)}
}
def private ce_channel_send_poll(var op:auto(O)?) {unsafe {
    var state=op.state
    if(state.closed) {return task_ready(result_error(empty(state.error) ? "channel is closed" : state.error,type<CeUnit>))}
    if(op.id==uint64(0)) {op.id=ce_channel_register(state,true)}
    if(state.senders[0]==op.id && length(state.queue)<state.capacity) {
        state.queue |> emplace(op.value)
        ce_channel_remove(state.senders,op.id);op.id=uint64(0)
        return task_ready(result_ok(CeUnit()))
    }
    return task_pending(type<$Result<CeUnit;string>>)
}}
def private ce_channel_finish(var op:auto(O)?;sender:bool) {unsafe {
    if(sender) {ce_channel_remove(op.state.senders,op.id)} else {ce_channel_remove(op.state.readers,op.id)}
    op.state=null;delete op.lease;delete op
}}
def task_channel_send_move(channel:tuple<tag:TaskChannelTag;owner:iterator<auto(S)?>>;var value:auto(T)) {
    var lease <- task_channel_clone(channel);var state=ce_channel_state(channel)
    unsafe {
        var op=new tuple<state:S?;lease:typedecl(lease);id:uint64;value:T -const -&>(state=state,lease <- lease,value <- value)
        return <- task_from_poll(@(){return ce_channel_send_poll(op)},@(){ce_channel_finish(op,true)})
    }
}
def task_channel_send(channel:tuple<tag:TaskChannelTag;owner:iterator<auto(S)?>>;value:auto(T)) {
    concept_assert(typeinfo can_copy(type<T>),"task channel: use task_channel_send_move for an owning payload")
    static_if(typeinfo is_string(type<T>)) {var item=string(value);return <- task_channel_send_move(channel,item)}
    else {var item=value;return <- task_channel_send_move(channel,item)}
}
def private ce_channel_receive_poll(var op:auto(O)?) {unsafe {
    var state=op.state
    typedef Item=typedecl(state.queue[0]) -const -&
    if(!empty(state.error)) {var error <- move_error(state.error,type<$Option<Item>>);return <- task_ready_move(error)}
    if(op.id==uint64(0)) {op.id=ce_channel_register(state,false)}
    if(state.readers[0]==op.id) {
        if(!empty(state.queue)) {
            var item <- ce_move_some(state.queue[0]);state.queue |> erase(0)
            ce_channel_remove(state.readers,op.id);op.id=uint64(0)
            var result <- move_ok(item);return <- task_ready_move(result)
        }
        if(state.closed) {var item=none(type<Item>);var result <- move_ok(item);return <- task_ready_move(result)}
    }
    return <- task_pending(type<$Result<$Option<Item>;string>>)
}}
def task_channel_receive(channel:tuple<tag:TaskChannelTag;owner:iterator<auto(S)?>>) {
    var lease <- task_channel_clone(channel);var state=ce_channel_state(channel)
    unsafe {
        var op=new tuple<state:S?;lease:typedecl(lease);id:uint64>(state=state,lease <- lease)
        return <- task_from_poll(@(){return <- ce_channel_receive_poll(op)},@(){ce_channel_finish(op,false)})
    }
}

def clone(var target:tuple<tag:TaskChannelTag;owner:iterator<auto(S)?>>;source:tuple<tag:TaskChannelTag;owner:iterator<S?>>) {
    var next <- task_channel_clone(source);delete target;target <- next
}
