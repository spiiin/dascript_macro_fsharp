options gen2
module rx_scheduler public
require daslib/rtti

struct RxScheduledId {owner:uint64;id:uint64}
struct RxScheduledAction {
    id:uint64
    due:int64
    action:lambda<():void>
    on_close:lambda<():void>
}
struct RxSchedulerCloseHook {id:uint64;action:lambda<():void>}
struct RxSchedulerState {
    references:int=1
    owner:uint64
    serial:uint64
    now_ms:int64
    virtual_time:bool
    busy:bool
    closed:bool
    queue:array<RxScheduledAction>
    close_hooks:array<RxSchedulerCloseHook>
}
struct RxScheduler {owner:iterator<RxSchedulerState?>}
var private rx_clock_serial=uint64(0)
def private rx_clock_finalize(action:block<():void>) {try {panic("__rx_clock_finalize")} recover {invoke(action)}}
def private rx_clock_close(var state:RxSchedulerState?) : void {
    unsafe {
        if(state.closed) {return}
        state.closed=true
        var actions <- state.queue
        var hooks <- state.close_hooks
        var failed=false
        var message=""
        for(item in hooks) {
            try {invoke(item.action)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        }
        for(item in actions) {
            try {invoke(item.on_close)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        }
        delete actions;delete hooks
        if(failed) {panic(message)}
    }
}
def private rx_clock_lease(var state:RxSchedulerState?;primary:bool) {
    return <- generator<RxSchedulerState?> capture(copy(state),copy(primary)) {
        while(true) {yield state}
        return false
    } finally {rx_clock_finalize($ {
        var failed=false
        var message=""
        if(primary) {try {rx_clock_close(state)} recover {failed=true;message="{this_context().last_exception}"}}
        unsafe {state.references--;if(state.references==0) {delete state}}
        if(failed) {panic(message)}
    })}
}
def private rx_clock_state(scheduler:RxScheduler) : RxSchedulerState? {
    if(empty(scheduler.owner)) {panic("rx scheduler: handle was moved or deleted")}
    unsafe {
        var owner=reinterpret<iterator<RxSchedulerState?>?>(addr(scheduler.owner))
        var state:RxSchedulerState?
        if(!next(*owner,state)) {panic("rx scheduler: invalid handle")}
        return state
    }
}
def private rx_clock_create(start_ms:int64;virtual_time:bool) {
    if(start_ms<0) {panic("rx scheduler: time must be nonnegative")}
    if(rx_clock_serial==uint64(-1)) {panic("rx scheduler: identities exhausted")}
    rx_clock_serial++
    return <- RxScheduler(owner <- rx_clock_lease(new RxSchedulerState(owner=rx_clock_serial,now_ms=start_ms,virtual_time=virtual_time),true))
}
def rx_scheduler(start_ms:int64=0l) {return <- rx_clock_create(start_ms,false)}
def rx_scheduler(start_ms:int) {return <- rx_clock_create(int64(start_ms),false)}
def rx_virtual_scheduler(start_ms:int64=0l) {return <- rx_clock_create(start_ms,true)}
def rx_virtual_scheduler(start_ms:int) {return <- rx_clock_create(int64(start_ms),true)}
def rx_scheduler_clone(scheduler:RxScheduler) {
    var state=rx_clock_state(scheduler)
    unsafe {state.references++}
    return <- RxScheduler(owner <- rx_clock_lease(state,false))
}
def rx_now_ms(scheduler:RxScheduler) : int64 {unsafe {return rx_clock_state(scheduler).now_ms}}
def rx_scheduler_closed(scheduler:RxScheduler) : bool {unsafe {return rx_clock_state(scheduler).closed}}
def rx_pending_count(scheduler:RxScheduler) : int {unsafe {return length(rx_clock_state(scheduler).queue)}}
def rx_close_listener_count(scheduler:RxScheduler) : int {unsafe {return length(rx_clock_state(scheduler).close_hooks)}}
def rx_scheduler_close(scheduler:RxScheduler) {rx_clock_close(rx_clock_state(scheduler))}
def rx_on_scheduler_close(scheduler:RxScheduler;var action:lambda<():void>) : RxScheduledId {
    var state=rx_clock_state(scheduler)
    unsafe {
        if(state.closed) {
            var failed=false
            var message=""
            try {invoke(action)} recover {failed=true;message="{this_context().last_exception}"}
            delete action
            if(failed) {panic(message)}
            return RxScheduledId()
        }
        if(state.serial==uint64(-1)) {delete action;panic("rx scheduler: IDs exhausted")}
        state.serial++
        state.close_hooks |> emplace(RxSchedulerCloseHook(id=state.serial,action <- action))
        return RxScheduledId(owner=state.owner,id=state.serial)
    }
}
def rx_schedule(scheduler:RxScheduler;duration_ms:int64|int;var action,on_close:lambda<():void>) : RxScheduledId {
    let delay_ms=int64(duration_ms)
    var state=rx_clock_state(scheduler)
    unsafe {
        if(state.closed || state.serial==uint64(-1) || delay_ms<0 || delay_ms>9223372036854775807l-state.now_ms) {
            delete action;delete on_close
            panic("rx schedule: closed scheduler, exhausted IDs, negative delay or deadline overflow")
        }
        state.serial++
        let id=state.serial
        state.queue |> emplace(RxScheduledAction(id=id,due=state.now_ms+delay_ms,action <- action,on_close <- on_close))
        return RxScheduledId(owner=state.owner,id=id)
    }
}
def rx_schedule(scheduler:RxScheduler;delay_ms:int64|int;var action:lambda<():void>) : RxScheduledId {
    return rx_schedule(scheduler,delay_ms,action,@(){})
}
def rx_cancel(scheduler:RxScheduler;id:RxScheduledId) : bool {
    var state=rx_clock_state(scheduler)
    unsafe {
        if(id.owner!=state.owner) {return false}
        for(i in range(length(state.queue))) {
            if(state.queue[i].id==id.id) {
                var removed <- state.queue[i]
                state.queue |> erase(i)
                delete removed
                return true
            }
        }
        for(i in range(length(state.close_hooks))) {
            if(state.close_hooks[i].id==id.id) {
                var removed <- state.close_hooks[i]
                state.close_hooks |> erase(i)
                delete removed
                return true
            }
        }
    }
    return false
}
def private rx_clock_run(scheduler:RxScheduler;target_ms:int64;virtual_time:bool;max_actions:int) : int {
    // Retain storage if a callback deletes the primary scheduler handle.
    var retained <- rx_scheduler_clone(scheduler)
    var state=rx_clock_state(retained)
    var count=0
    var failed=false
    var message=""
    unsafe {
        if(state.busy || state.virtual_time!=virtual_time || target_ms<state.now_ms || max_actions<=0) {
            delete retained
            panic("rx scheduler: invalid mode, reentrant tick, backwards time or action budget")
        }
        if(state.closed) {delete retained;return 0}
        state.busy=true
        if(!virtual_time) {state.now_ms=target_ms}
        try {
            while(!state.closed && count<max_actions) {
                var best=-1
                for(i in range(length(state.queue))) {
                    if(state.queue[i].due<=target_ms && (best<0 || state.queue[i].due<state.queue[best].due || (state.queue[i].due==state.queue[best].due && state.queue[i].id<state.queue[best].id))) {best=i}
                }
                if(best<0) {break}
                var item <- state.queue[best]
                state.queue |> erase(best)
                if(virtual_time) {state.now_ms=item.due>state.now_ms ? item.due : state.now_ms}
                var actionFailed=false
                var actionMessage=""
                try {invoke(item.action)} recover {actionFailed=true;actionMessage="{this_context().last_exception}"}
                delete item
                count++
                if(actionFailed) {panic(actionMessage)}
            }
            // A budget-limited virtual advance remains at the last executed
            // deadline if more work is due. Calling advance_to again resumes it.
            var pending=false
            for(item in state.queue) {if(item.due<=target_ms) {pending=true;break}}
            if(!pending) {state.now_ms=target_ms}
        } recover {failed=true;message="{this_context().last_exception}"}
        state.busy=false
    }
    delete retained
    if(failed) {panic(message)}
    return count
}
def rx_tick(scheduler:RxScheduler;now_ms:int64|int;max_actions:int=10000) : int {return rx_clock_run(scheduler,int64(now_ms),false,max_actions)}
def rx_advance_to(scheduler:RxScheduler;now_ms:int64|int;max_actions:int=10000) : int {return rx_clock_run(scheduler,int64(now_ms),true,max_actions)}
def rx_advance_by(scheduler:RxScheduler;duration:int64|int;max_actions:int=10000) : int {
    let duration_ms=int64(duration)
    if(duration_ms<0 || duration_ms>9223372036854775807l-rx_now_ms(scheduler)) {panic("rx advance: negative duration or time overflow")}
    return rx_advance_to(scheduler,rx_now_ms(scheduler)+duration_ms,max_actions)
}
