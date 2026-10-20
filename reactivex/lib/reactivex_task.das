options gen2
module reactivex_task public
require ./reactivex.das public
require ../../computation_expressions/lib/task_delay.das public

// Adapter storage is shared by a Task's callbacks and an Rx subscription.
// A callback lease keeps its data valid if cancellation removes its listener.
def private rx_bridge_finalize(action:block<():void>) {try {panic("__rx_bridge_finalize")} recover {invoke(action)}}
def private rx_bridge_lease(var state:auto(S)?) {
    return <- generator<S?> capture(copy(state)) {
        while(true) {yield state}
        return false
    } finally {rx_bridge_finalize($ {unsafe {state.references--;if(state.references==0) {delete state}}})}
}
def private rx_bridge_node(var data:auto) {
    var state=new tuple<references:int;data:typedecl(data) -const -&>(references=1,data <- data)
    unsafe {return <- typeinfo rx_normalized((owner <- rx_bridge_lease(state)))}
}
def private rx_bridge_state(handle:tuple<owner:iterator<auto(S)?>>) : S? {
    unsafe {
        var lease=reinterpret<iterator<S?>?>(addr(handle.owner))
        var state:S?
        if(!next(*lease,state)) {panic("rx task: invalid adapter lease")}
        return state
    }
}
def private rx_bridge_ref(handle:tuple<owner:iterator<auto?>>) {
    var state=rx_bridge_state(handle)
    unsafe {state.references++}
    return <- (owner <- rx_bridge_lease(state))
}
def private rx_first_poll(op:tuple<owner:iterator<auto?>>;marker:type<auto(T)>) {
    unsafe {
        let state=rx_bridge_state(op)
        if(!state.data.started) {
            state.data.started=true
            var values <- rx_bridge_ref(op)
            var errors <- rx_bridge_ref(op)
            var completed <- rx_bridge_ref(op)
            var on_next <- @ capture(<-values) (value:T) {
                unsafe {
                    let target=rx_bridge_state(values)
                    if(target.data.ready) {return}
                    target.data.value=value;target.data.ready=true
                    rx_unsubscribe(target.data.control)
                }
            } finally {rx_bridge_finalize($ {delete values})}
            var on_error <- @ capture(<-errors) (message:string) {
                unsafe {
                    let target=rx_bridge_state(errors)
                    if(!target.data.ready) {target.data.ready=true;target.data.failed=true;target.data.error=string(message)}
                }
            } finally {rx_bridge_finalize($ {delete errors})}
            var on_complete <- @ capture(<-completed) () {
                unsafe {
                    let target=rx_bridge_state(completed)
                    if(!target.data.ready) {target.data.ready=true;target.data.failed=true;target.data.error="rx: source completed without value"}
                }
            } finally {rx_bridge_finalize($ {delete completed})}
            rx_subscribe_with(state.data.control,state.data.source,on_next,on_error,on_complete)
        }
        // Do not export deduction constness into a variant member: SDK AOT emits
        // distinct C++ TVariant types for string and const string payloads.
        if(!state.data.ready) {return task_pending(type<$Result<T -const -&;string>>)}
        if(state.data.failed) {return task_ready(result_error(state.data.error,type<T>))}
        return task_ready(result_ok(state.data.value))
    }
}
def rx_first_task(source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>) {
    var op <- rx_bridge_node((source <- rx_clone(source),control <- rx_subscription(),started=false,ready=false,failed=false,value=default<T>,error=""))
    var poll <- rx_bridge_ref(op)
    var close <- rx_bridge_ref(op)
    delete op
    return <- task_from_poll(@ capture(<-poll) () {return rx_first_poll(poll,type<T>)} finally {rx_bridge_finalize($ {delete poll})},
        @ capture(<-close) () {unsafe {rx_unsubscribe(rx_bridge_state(close).data.control)}} finally {rx_bridge_finalize($ {delete close})})
}

struct RxTaskValuePolicy {_marker:uint8}
struct RxTaskResultPolicy {_marker:uint8}
var private rx_task_clock_serial=uint64(0)
// Shared identity allocator for Rx adapters that poll CE continuations.
def rx_adapter_clock_identity() : uint64 {
    if(rx_task_clock_serial==uint64(-1)) {panic("rx adapter: clock identities exhausted")}
    rx_task_clock_serial++
    return uint64(-1)-rx_task_clock_serial
}

def private rx_task_dispose(op:auto) : void {
    unsafe {
        let state=rx_bridge_state(op)
        if(state.data.disposed) {return}
        state.data.disposed=true
        let cancelled=task_cancel(state.data.task)
        let failed=cancelled && task_status(state.data.task)==TaskStatus.Failed
        let message=failed ? string(task_error(state.data.task)) : ""
        delete state.data.task
        if(failed) {panic(message)}
    }
}
def private rx_task_stop(op:auto) : void {
    unsafe {
        let state=rx_bridge_state(op)
        state.data.stopped=true
        rx_cancel(state.data.clock,state.data.scheduled)
        rx_cancel(state.data.clock,state.data.lifecycle)
        // Never destroy a generator while its continuation is on the stack.
        if(!state.data.polling) {rx_task_dispose(op)}
    }
}
def private rx_task_deliver(op:auto;policy:RxTaskValuePolicy) : void {
    unsafe {
        let state=rx_bridge_state(op)
        let value=task_value(state.data.task)
        // Success is committed before entering user callbacks. A callback may
        // close the scheduler; that must not turn this result into nested error.
        rx_task_stop(op)
        rx_sink_next(state.data.sink,value)
        if(!rx_sink_stopped(state.data.sink)) {rx_sink_complete(state.data.sink)}
    }
}
def private rx_task_deliver(op:auto;policy:RxTaskResultPolicy) : void {
    unsafe {
        let state=rx_bridge_state(op)
        let result=task_value(state.data.task)
        rx_task_stop(op)
        if(result is err) {rx_sink_error(state.data.sink,result as err)}
        else {
            rx_sink_next(state.data.sink,result as ok)
            if(!rx_sink_stopped(state.data.sink)) {rx_sink_complete(state.data.sink)}
        }
    }
}
def private rx_task_poll(op:auto) : void {
    unsafe {
        let state=rx_bridge_state(op)
        if(state.data.stopped || rx_sink_stopped(state.data.sink)) {return}
        state.data.polling=true
        var status=TaskStatus.Created
        var failed=false
        var message=""
        try {ce_task_clock_scope(state.data.clock_owner,rx_now_ms(state.data.clock),$ {status=task_poll(state.data.task)})} recover {failed=true;message="{this_context().last_exception}"}
        state.data.polling=false
        if(state.data.stopped || rx_sink_stopped(state.data.sink)) {rx_task_dispose(op);return}
        if(failed) {rx_sink_error(state.data.sink,message);return}
        if(status==TaskStatus.Failed) {let error=string(task_error(state.data.task));rx_sink_error(state.data.sink,error)}
        elif(status==TaskStatus.Cancelled) {rx_sink_error(state.data.sink,"rx task cancelled")}
        elif(status==TaskStatus.Succeeded) {rx_task_deliver(op,state.data.policy)}
        else {rx_task_schedule(op,state.data.period)}
    }
}
def private rx_task_schedule(op:auto;duration:int64) : void {
    unsafe {
        let state=rx_bridge_state(op)
        if(state.data.stopped || rx_sink_stopped(state.data.sink)) {return}
        var owner <- rx_bridge_ref(op)
        var closing <- rx_bridge_ref(op)
        var action <- @ capture(<-owner) () {rx_task_poll(owner)} finally {rx_bridge_finalize($ {delete owner})}
        var on_close <- @ capture(<-closing) () {unsafe {rx_sink_error(rx_bridge_state(closing).data.sink,"rx scheduler closed")}} finally {rx_bridge_finalize($ {delete closing})}
        var failed=false
        var message=""
        try {state.data.scheduled=rx_schedule(state.data.clock,duration,action,on_close)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {rx_sink_error(state.data.sink,message)}
    }
}
def private rx_task_factory(var factory:auto;scheduler:RxScheduler;period:int64;policy:auto;marker:auto(S)) : lambda<(sink:S):void> {
    var clock <- rx_scheduler_clone(scheduler)
    return <- @ capture(<-factory,<-clock,copy(period),copy(policy)) (sink:S) {
        var task:typedecl(invoke(factory)) -const -&
        var failed=false
        var message=""
        try {task <- invoke(factory)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {delete task;rx_sink_error(sink,message);return}
        // An adapter run has a stable private clock identity, independent of a
        // CE TaskScheduler and of other subscriptions to the same Observable.
        let clockIdentity=rx_adapter_clock_identity()
        var op <- rx_bridge_node((task <- task,sink <- rx_sink_clone(sink),clock <- rx_scheduler_clone(clock),
            period=period,policy=policy,scheduled=RxScheduledId(),lifecycle=RxScheduledId(),clock_owner=clockIdentity,
            polling=false,stopped=false,disposed=false))
        var closing <- rx_bridge_ref(op)
        rx_sink_add_cleanup(sink,@ capture(<-closing) () {rx_task_stop(closing)} finally {rx_bridge_finalize($ {delete closing})})
        failed=false;message=""
        try {
            unsafe {
                let state=rx_bridge_state(op)
                if(!state.data.stopped && !rx_sink_stopped(sink)) {
                    var guard <- rx_bridge_ref(op)
                    var on_close <- @ capture(<-guard) () {unsafe {rx_sink_error(rx_bridge_state(guard).data.sink,"rx scheduler closed")}} finally {rx_bridge_finalize($ {delete guard})}
                    state.data.lifecycle=rx_on_scheduler_close(state.data.clock,on_close)
                }
            }
            rx_task_schedule(op,0l)
        } recover {failed=true;message="{this_context().last_exception}"}
        delete op
        if(failed) {panic(message)}
    } finally {rx_bridge_finalize($ {unsafe {delete factory};delete clock})}
}
def private rx_task_value_node(var factory:auto;scheduler:RxScheduler;period:int64;
    marker:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:auto(T)>>;status:TaskStatus;value:T;error:string;polling:bool>) {
    var wrapper <- rx_task_factory(factory,scheduler,period,RxTaskValuePolicy(),rx_sink_marker(type<T>))
    return <- rx_create(type<T>,wrapper)
}
def private rx_task_result_node(var factory:auto;scheduler:RxScheduler;period:int64;
    marker:tuple<tag:TaskTag;source:iterator<tuple<tag:TaskEventTag;ready:bool;value:$Result<auto(RxBridgeResult);string>>>;status:TaskStatus;value:$Result<RxBridgeResult;string>;error:string;polling:bool>) {
    var wrapper <- rx_task_factory(factory,scheduler,period,RxTaskResultPolicy(),rx_sink_marker(type<RxBridgeResult>))
    return <- rx_create(type<RxBridgeResult>,wrapper)
}
def rx_from_task(var factory:auto;scheduler:RxScheduler;poll_ms:int64=1l) {
    if(poll_ms<=0) {unsafe {delete factory};panic("rx_from_task: poll period must be positive")}
    return <- rx_task_value_node(factory,scheduler,poll_ms,default<typedecl(invoke(factory))>)
}
def rx_from_task_result(var factory:auto;scheduler:RxScheduler;poll_ms:int64=1l) {
    if(poll_ms<=0) {unsafe {delete factory};panic("rx_from_task_result: poll period must be positive")}
    return <- rx_task_result_node(factory,scheduler,poll_ms,default<typedecl(invoke(factory))>)
}
def rx_from_task(var factory:auto;scheduler:RxScheduler;poll_ms:int) {return <- rx_from_task(factory,scheduler,int64(poll_ms))}
def rx_from_task_result(var factory:auto;scheduler:RxScheduler;poll_ms:int) {return <- rx_from_task_result(factory,scheduler,int64(poll_ms))}
