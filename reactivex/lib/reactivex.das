options gen2
module reactivex public
require daslib/rtti
require ./rx_payload_checks.das public
require ./rx_scheduler.das public

// A zero limit is internal/backward-compatible unbounded storage.
// Construct field snapshots when embedding settings in node/run tuples:
// native tuple initialization can otherwise move a borrowed struct field.
enum RxOverflowPolicy {
    error
    drop_oldest
    drop_latest
}
struct RxQueueOptions {
    capacity:int
    policy:RxOverflowPolicy=RxOverflowPolicy.error
}
def rx_queue(capacity:int;policy:RxOverflowPolicy=RxOverflowPolicy.error) : RxQueueOptions {
    if(capacity<=0) {panic("rx_queue: capacity must be positive")}
    return RxQueueOptions(capacity=capacity,policy=policy)
}
def private rx_queue_validate(queue_options:RxQueueOptions) {
    if(queue_options.capacity<0) {panic("rx queue: negative capacity")}
    if(queue_options.policy!=RxOverflowPolicy.error && queue_options.policy!=RxOverflowPolicy.drop_oldest && queue_options.policy!=RxOverflowPolicy.drop_latest) {panic("rx queue: invalid overflow policy")}
}
def private rx_queue_dispose(var value:auto) {
    static_if(typeinfo can_delete(type<typedecl(value) -const -&>)) {delete value}
}
// Remove owning payloads before invoking their finalizer (which can reenter).
def private rx_queue_drop_first(var values:array<auto(QueueValue)>) {
    var removed <- values[0]
    values |> erase(0)
    static_if(typeinfo can_delete(type<QueueValue>)) {delete removed}
}
def private rx_queue_full(size:int;queue_options:RxQueueOptions) : bool {return queue_options.capacity>0 && size>=queue_options.capacity}

// Single-threaded ownership: only the returned subscription lease auto-disposes.
// Internal leases retain storage without keeping an active subscription alive.
struct RxSubscriptionState {
    references:int=1
    closed:bool
    started:bool
    cleanup:array<lambda<():void>>
}
struct RxSubscription {owner:iterator<RxSubscriptionState?>}
struct RxObserverTag {_marker:uint8}
struct RxRangeTag {_marker:uint8}
struct RxArrayTag {_marker:uint8}
struct RxMapTag {_marker:uint8}
struct RxFilterTag {_marker:uint8}
struct RxTakeTag {_marker:uint8}
struct RxSkipTag {_marker:uint8}
struct RxTakeWhileTag {_marker:uint8}
struct RxSkipWhileTag {_marker:uint8}
struct RxPairwiseTag {_marker:uint8}
struct RxFinallyTag {_marker:uint8}
struct RxTapTag {_marker:uint8}
struct RxScanTag {_marker:uint8}
struct RxDistinctTag {_marker:uint8}
struct RxDeferTag {_marker:uint8}
struct RxSubjectTag {_marker:uint8}

// LambdaIterator finalizers inherit native break/return flags on this SDK.
def private rx_finalize(action:block<():void>) {
    try {panic("__rx_finalize_entry")} recover {invoke(action)}
}

// Internal observers retain control storage inline. Only the public primary
// lease closes a subscription when destroyed; these references never close it.
// The empty iterator prevents accidental copies without allocating storage.
// Visible to client-side generic tuple finalization on this SDK.
struct RxControlRef {
    state:RxSubscriptionState?
    unique:iterator<uint8>
    def finalize {
        var retained=state
        state=null
        if(retained!=null) {rx_finalize($ {unsafe {
            retained.references--
            if(retained.references==0) {delete retained}
        }})}
    }
}

def private rx_cleanup(var state:RxSubscriptionState?) {
    unsafe {
        var actions <- state.cleanup
        var message=""
        var failed=false
        for(action in actions) {
            try {invoke(action)} recover {
                if(!failed) {message="{this_context().last_exception}";failed=true}
            }
        }
        delete actions
        if(failed) {panic(message)}
    }
}
def private rx_close_state(var state:RxSubscriptionState?) : bool {
    unsafe {
        if(state.closed) {return false}
        state.closed=true
        rx_cleanup(state)
        return true
    }
}
def private rx_subscription_lease(var state:RxSubscriptionState?;primary:bool) {
    return <- generator<RxSubscriptionState?> capture(copy(state),copy(primary)) {
        while(true) {yield state}
        return false
    } finally {rx_finalize($ {
        var message=""
        var failed=false
        if(primary) {try {rx_close_state(state)} recover {message="{this_context().last_exception}";failed=true}}
        unsafe {state.references--;if(state.references==0) {delete state}}
        if(failed) {panic(message)}
    })}
}
def rx_subscription() {return <- RxSubscription(owner <- rx_subscription_lease(new RxSubscriptionState(),true))}

def private rx_control(subscription:RxSubscription) : RxSubscriptionState? {
    if(empty(subscription.owner)) {panic("rx: subscription was moved or deleted")}
    unsafe {
        var owner=reinterpret<iterator<RxSubscriptionState?>?>(addr(subscription.owner))
        var state:RxSubscriptionState?
        if(!next(*owner,state)) {panic("rx: invalid subscription")}
        return state
    }
}
def private rx_control(subscription:RxControlRef) : RxSubscriptionState? {unsafe {return reinterpret<RxSubscriptionState?>(subscription.state)}}
def private rx_subscription_ref(subscription:RxSubscription) {
    var state=rx_control(subscription)
    unsafe {state.references++}
    return <- RxSubscription(owner <- rx_subscription_lease(state,false))
}
def private rx_observer_control(subscription:RxSubscription|RxControlRef) {
    var state=rx_control(subscription)
    unsafe {state.references++}
    return <- RxControlRef(state=state)
}
def private rx_is_closed(subscription:RxControlRef) : bool {unsafe {return subscription.state.closed}}
def private rx_unsubscribe(subscription:RxControlRef) : bool {return rx_close_state(rx_control(subscription))}
def rx_is_closed(subscription:RxSubscription) : bool {
    if(empty(subscription.owner)) {return true}
    unsafe {return rx_control(subscription).closed}
}
def rx_unsubscribe(subscription:RxSubscription) : bool {
    if(empty(subscription.owner)) {return false}
    return rx_close_state(rx_control(subscription))
}
def private rx_add_cleanup_state(var state:RxSubscriptionState?;var action:lambda<():void>) {
    unsafe {
        if(state.closed) {
            var message=""
            var failed=false
            try {invoke(action)} recover {message="{this_context().last_exception}";failed=true}
            delete action
            if(failed) {panic(message)}
        } else {state.cleanup |> push <| action}
    }
}
def rx_add_cleanup(subscription:RxSubscription;var action:lambda<():void>) {rx_add_cleanup_state(rx_control(subscription),action)}
def private rx_add_cleanup(subscription:RxControlRef;var action:lambda<():void>) {rx_add_cleanup_state(rx_control(subscription),action)}

// Nodes/observer storage are shared only through explicit owning leases.
def private rx_lease(var state:auto(S)?) {
    return <- generator<S?> capture(copy(state)) {
        while(true) {yield state}
        return false
    } finally {rx_finalize($ {unsafe {state.references--;if(state.references==0) {delete state}}})}
}
def private rx_state(handle:tuple<tag:auto;owner:iterator<auto(S)?>>) : S? {
    if(empty(handle.owner)) {panic("rx: handle was moved or deleted")}
    unsafe {
        var owner=reinterpret<iterator<S?>?>(addr(handle.owner))
        var state:S?
        if(!next(*owner,state)) {panic("rx: handle was moved or deleted")}
        return state
    }
}
def private rx_state(handle:tuple<tag:auto;owner:iterator<auto(S)?>;element:auto>) : S? {
    if(empty(handle.owner)) {panic("rx: observable was moved or deleted")}
    unsafe {
        var owner=reinterpret<iterator<S?>?>(addr(handle.owner))
        var state:S?
        if(!next(*owner,state)) {panic("rx: observable was moved or deleted")}
        return state
    }
}
def private rx_ref(handle:tuple<tag:auto(Tag);owner:iterator<auto(S)?>>) {
    var state=rx_state(handle)
    unsafe {state.references++}
    return <- (tag=Tag(),owner <- rx_lease(state))
}
def private rx_ref(handle:tuple<tag:auto(Tag);owner:iterator<auto(S)?>;element:iterator<auto(T)>>) {
    var state=rx_state(handle)
    unsafe {state.references++}
    var marker:iterator<T -const -&>
    return <- (tag=Tag(),owner <- rx_lease(state),element <- marker)
}
def private rx_check_payload(unused:type<auto(RxCheckedValue)>) {
    static_assert(typeinfo rx_payload(default<RxCheckedValue>))
    concept_assert(typeinfo can_copy(type<RxCheckedValue>),"rx: broadcast elements must be copyable; move-only payloads are not supported; map borrowed buffer batches to a copyable value before retaining operators")
}
def private rx_storage_node(tag:auto;var data:auto;unused:type<auto(RxStoredValue)>) {
    var state=new tuple<references:int;data:typedecl(data) -const -&>(references=1,data <- data)
    var marker:iterator<RxStoredValue -const -&>
    unsafe {return <- typeinfo rx_normalized((tag=tag,owner <- rx_lease(state),element <- marker))}
}
def private rx_node(tag:auto;var data:auto;unused:type<auto(RxNodeValue)>) {
    rx_check_payload(type<RxNodeValue>)
    return <- rx_storage_node(tag,data,type<RxNodeValue>)
}
// Buffer batches are owned by their delivery frame and borrowed by callbacks.
// Only non-retaining pass-through nodes may propagate an array-valued batch.
def private rx_node(tag:RxFilterTag|RxTakeTag|RxTapTag|RxSkipTag|RxTakeWhileTag|RxSkipWhileTag|RxFinallyTag;var data:auto;unused:type<array<auto(BatchItem)>>) {
    rx_check_payload(type<BatchItem>)
    return <- rx_storage_node(tag,data,type<array<BatchItem>>)
}

def private rx_node(tag:RxFilterTag|RxTakeTag|RxTapTag|RxSkipTag|RxTakeWhileTag|RxSkipWhileTag|RxFinallyTag;var data:auto;unused:type<tuple<tag:auto(WindowTag);owner:iterator<auto(WindowState)?>;element:iterator<auto(WindowValue)>>>) {
    return <- rx_storage_node(tag,data,type<tuple<tag:WindowTag;owner:iterator<WindowState?>;element:iterator<WindowValue>>>)
}

def private rx_observer_marker(unused:type<auto(T)>) {
    var owner:iterator<tuple<references:int;control:RxControlRef;stopped:bool;root:bool;on_next:lambda<(value:T):void>;on_error:lambda<(message:string):void>;on_complete:lambda<():void>>?>
    return <- (tag=RxObserverTag(),owner <- owner)
}
def private rx_observer(control:RxSubscription|RxControlRef;var on_next:lambda<(value:auto(T)):void>;var on_error:lambda<(message:string):void>;var on_complete:lambda<():void>;root:bool=true) {
    var state=new tuple<references:int;control:RxControlRef;stopped:bool;root:bool;on_next:lambda<(value:T):void>;on_error:lambda<(message:string):void>;on_complete:lambda<():void>>(references=1,control <- rx_observer_control(control),root=root,on_next <- on_next,on_error <- on_error,on_complete <- on_complete)
    return <- (tag=RxObserverTag(),owner <- rx_lease(state))
}
// A synchronous dispatch can pin storage directly, without allocating a lease.
def private rx_release_state(var state:auto?) {
    unsafe {state.references--;if(state.references==0) {delete state}}
}

def private rx_next_state(var state:auto?;value:auto) {
    unsafe {
        if(state.stopped || rx_is_closed(state.control)) {return}
        var message=""
        var failed=false
        try {invoke(state.on_next,value)} recover {message="{this_context().last_exception}";failed=true}
        if(failed) {
            try {rx_unsubscribe(state.control)} recover {}
            panic(message)
        }
    }
}

def private rx_next(observer:auto;value:auto) {rx_next_state(rx_state(observer),value)}
def private rx_terminal_state(var state:auto?;error:bool;message:string="") {
    unsafe {
        var control=rx_control(state.control)
        if(state.stopped || control.closed) {return}
        state.stopped=true
        if(state.root) {control.closed=true}
        var failure=""
        var failed=false
        try {
            if(error) {invoke(state.on_error,message)} else {invoke(state.on_complete)}
        } recover {failure="{this_context().last_exception}";failed=true}
        if(state.root) {try {rx_cleanup(control)} recover {if(!failed) {failure="{this_context().last_exception}";failed=true}}}
        if(failed) {panic(failure)}
    }
}
def private rx_terminal(observer:auto;error:bool;message:string="") {rx_terminal_state(rx_state(observer),error,message)}
def private rx_done(observer:auto) {rx_terminal(observer,false)}
def private rx_error(observer:auto;message:string) {rx_terminal(observer,true,message)}
def private rx_stopped(observer:auto) : bool {unsafe {return rx_is_closed(rx_state(observer).control)}}

def rx_subscribe_with(control:RxSubscription;source:auto;var on_next:lambda<(value:auto):void>;var on_error:lambda<(message:string):void>;var on_complete:lambda<():void>) {
    var state=rx_control(control)
    unsafe {
        if(state.started || state.closed) {
            delete on_next;delete on_error;delete on_complete
            if(state.started) {panic("rx: subscription has already been used")}
            state.started=true
            return
        }
        state.started=true
    }
    var inscope retained <- rx_ref(source)
    var inscope observer <- rx_observer(control,on_next,on_error,on_complete)
    var failure=""
    var failed=false
    try {rx_connect(retained,observer)} recover {failure="{this_context().last_exception}";failed=true}
    if(failed) {try {rx_unsubscribe(control)} recover {}}
    delete observer
    delete retained
    if(failed) {panic(failure)}
}
def rx_subscribe(source:auto;var on_next:lambda<(value:auto):void>;var on_error:lambda<(message:string):void>;var on_complete:lambda<():void>) {
    var result <- rx_subscription()
    var failure=""
    var failed=false
    try {rx_subscribe_with(result,source,on_next,on_error,on_complete)} recover {failure="{this_context().last_exception}";failed=true}
    if(failed) {delete result;panic(failure)}
    return <- result
}

def rx_range(first,count:int) {
    if(count<0) {panic("rx_range: count must be nonnegative")}
    if(count>0 && int64(first)+int64(count)-1>2147483647l) {panic("rx_range: integer overflow")}
    return <- rx_node(RxRangeTag(),(first=first,count=count),type<int>)
}
def rx_from_array(values:array<auto(T)>) {
    var items:array<T>
    items := values
    return <- rx_node(RxArrayTag(),(items <- items),type<T>)
}
def rx_connect(source:tuple<tag:RxRangeTag;owner:iterator<auto?>;element:iterator<int>>;observer:auto) {
    var state=rx_state(source)
    unsafe {
        for(i in range(state.data.count)) {if(rx_stopped(observer)) {return};rx_next(observer,state.data.first+i)}
    }
    rx_done(observer)
}
def rx_connect(source:tuple<tag:RxArrayTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) {
    var state=rx_state(source)
    unsafe {
        for(item in state.data.items) {if(rx_stopped(observer)) {return};rx_next(observer,item)}
    }
    rx_done(observer)
}

def rx_map(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;var selector:lambda<(value:T):auto(U)>) {
    return <- rx_node(RxMapTag(),(source <- source,selector <- selector),type<U>)
}
def rx_filter(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;var predicate:auto) {
    return <- rx_node(RxFilterTag(),(source <- source,predicate <- predicate),type<T>)
}
def rx_take(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;count:int) {
    if(count<0) {panic("rx_take: count must be nonnegative")}
    return <- rx_node(RxTakeTag(),(source <- source,count=count),type<T>)
}
// These counters and predicate latches belong to a subscription, not a node.
def rx_skip(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;count:int) {
    if(count<0) {delete source;panic("rx_skip: count must be nonnegative")}
    return <- rx_node(RxSkipTag(),(source <- source,count=count),type<T>)
}

def rx_take_while(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;var predicate:lambda<(value:T):bool>) {
    return <- rx_node(RxTakeWhileTag(),(source <- source,predicate <- predicate),type<T>)
}

def rx_skip_while(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;var predicate:lambda<(value:T):bool>) {
    return <- rx_node(RxSkipWhileTag(),(source <- source,predicate <- predicate),type<T>)
}

def rx_pairwise(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>) {
    return <- rx_node(RxPairwiseTag(),(source <- source),type<tuple<previous:T -const -&;current:T -const -&>>)
}

def rx_finally(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;var action:lambda<():void>) {
    return <- rx_node(RxFinallyTag(),(source <- source,action <- action),type<T>)
}

def rx_defer(var factory:auto) {
    return <- rx_defer_node(factory,default<typedecl(invoke(factory))>)
}

// Stateful operators allocate their accumulator/history for each subscription.
def rx_tap(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(TapValue)>>;var on_next:lambda<(value:TapValue):void>;var on_error:lambda<(message:string):void>;var on_complete:lambda<():void>) {
    return <- rx_node(RxTapTag(),(source <- source,on_next <- on_next,on_error <- on_error,on_complete <- on_complete),type<TapValue>)
}
def rx_tap(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(TapValue)>>;var on_next:lambda<(value:TapValue):void>) {
    return <- rx_tap(source,on_next,@(message:string) {},@() {})
}
def rx_scan(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(ScanInput)>>;seed:auto(ScanState);var reducer:lambda<(state:ScanState;value:ScanInput):ScanState>) {
    static_if(typeinfo is_string(type<ScanState>)) {
        return <- rx_node(RxScanTag(),(source <- source,seed=string(seed),reducer <- reducer),type<ScanState>)
    } else {return <- rx_node(RxScanTag(),(source <- source,seed=seed,reducer <- reducer),type<ScanState>)}
}
def rx_distinct_until_changed(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(DistinctValue)>>;var equal:lambda<(previous:DistinctValue;current:DistinctValue):bool>) {
    return <- rx_node(RxDistinctTag(),(source <- source,equal <- equal),type<DistinctValue>)
}
def rx_distinct_until_changed(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(DistinctValue)>>) {
    return <- rx_distinct_until_changed(source,@(previous:DistinctValue;current:DistinctValue) {return previous==current})
}
def rx_start_with(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(PrefixValue)>>;value:PrefixValue) {
    var prefix <- rx_just(value)
    return <- rx_concat(prefix,source)
}

def private rx_tap_handler(keeper:auto;downstream:auto;input:iterator<auto(TapInput)>) {
    var node=rx_state(keeper)
    var target=rx_state(downstream)
    unsafe {node.references++;target.references++}
    var handler <- @ capture(copy(node),copy(target)) (value:TapInput) {
        var failed=false;var message=""
        unsafe {try {invoke(node.data.on_next,value)} recover {failed=true;message="{this_context().last_exception}"}}
        if(failed) {rx_terminal_state(target,true,message)} else {rx_next_state(target,value)}
    } finally {rx_finalize($ {rx_release_state(target);rx_release_state(node)})}
    return <- handler
}
def private rx_tap_finish(var keeper:auto?;var downstream:auto?;error:bool;message:string="") {
    var failed=false;var failure=""
    unsafe {
        try {
            if(error) {invoke(keeper.data.on_error,message)} else {invoke(keeper.data.on_complete)}
        } recover {failed=true;failure="{this_context().last_exception}"}
    }
    if(failed) {rx_terminal_state(downstream,true,failure)} else {rx_terminal_state(downstream,error,message)}
}
def rx_connect(source:tuple<tag:RxTapTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) {
    var state=rx_state(source)
    var errors=state;var errorSink=rx_state(observer)
    var completed=errors;var doneSink=errorSink
    unsafe {errors.references+=2;errorSink.references+=2}
    var error <- @ capture(copy(errors),copy(errorSink)) (message:string) {rx_tap_finish(errors,errorSink,true,message)} finally {rx_finalize($ {rx_release_state(errors);rx_release_state(errorSink)})}
    var done <- @ capture(copy(completed),copy(doneSink)) () {rx_tap_finish(completed,doneSink,false)} finally {rx_finalize($ {rx_release_state(completed);rx_release_state(doneSink)})}
    unsafe {
        var handler <- rx_tap_handler(source,observer,source.element)
        var inscope inner <- rx_observer(rx_state(observer).control,handler,error,done,false)
        rx_connect_inner(state.data.source,inner)
    }
}
def private rx_scan_handler(keeper:auto;downstream:auto;input:iterator<auto(ScanIn)>;var accumulator:auto(ScanAcc)) {
    var node=rx_state(keeper)
    var target=rx_state(downstream)
    unsafe {node.references++;target.references++}
    var handler <- @ capture(copy(node),copy(target),copy(accumulator)) (value:ScanIn) {
        var failed=false;var message=""
        unsafe {
            try {
                var updated=invoke(node.data.reducer,accumulator,value)
                static_if(typeinfo is_string(type<ScanAcc>)) {accumulator=string(updated)} else {accumulator=updated}
            } recover {failed=true;message="{this_context().last_exception}"}
        }
        if(failed) {rx_terminal_state(target,true,message)} else {rx_next_state(target,accumulator)}
    } finally {rx_finalize($ {rx_release_state(target);rx_release_state(node)})}
    return <- handler
}
def rx_connect(source:tuple<tag:RxScanTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) {
    var state=rx_state(source)
    unsafe {
        var seed=state.data.seed
        var handler <- rx_scan_handler(source,observer,state.data.source.element,seed)
        var inscope inner <- rx_forward(observer,handler)
        rx_connect_inner(state.data.source,inner)
    }
}
def private rx_distinct_handler(keeper:auto;downstream:auto;input:iterator<auto(DistinctInput)>) {
    var previous:DistinctInput
    var seen=false
    var node=rx_state(keeper)
    var target=rx_state(downstream)
    unsafe {node.references++;target.references++}
    var handler <- @ capture(copy(node),copy(target),copy(previous),copy(seen)) (value:DistinctInput) {
        var equal=false;var failed=false;var message=""
        unsafe {if(seen) {try {equal=invoke(node.data.equal,previous,value)} recover {failed=true;message="{this_context().last_exception}"}}}
        if(failed) {rx_terminal_state(target,true,message)} elif(!equal) {
            static_if(typeinfo is_string(type<DistinctInput>)) {previous=string(value)} else {previous=value}
            seen=true
            rx_next_state(target,value)
        }
    } finally {rx_finalize($ {rx_release_state(target);rx_release_state(node)})}
    return <- handler
}
def rx_connect(source:tuple<tag:RxDistinctTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) {
    var state=rx_state(source)
    unsafe {
        var handler <- rx_distinct_handler(source,observer,source.element)
        var inscope inner <- rx_forward(observer,handler)
        rx_connect_inner(state.data.source,inner)
    }
}
def private rx_defer_node(var factory:auto;marker:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>) {
    return <- rx_node(RxDeferTag(),(factory <- factory),type<T>)
}

def private rx_forward(downstream:auto;var on_next:lambda<(value:auto):void>) {
    var errors=rx_state(downstream)
    var completed=errors
    unsafe {errors.references+=2}
    var error <- @ capture(copy(errors)) (message:string) {rx_terminal_state(errors,true,message)} finally {rx_finalize($ {rx_release_state(errors)})}
    var done <- @ capture(copy(completed)) () {rx_terminal_state(completed,false)} finally {rx_finalize($ {rx_release_state(completed)})}
    unsafe {return <- rx_observer(rx_state(downstream).control,on_next,error,done,false)}
}
def private rx_map_handler(keeper:auto;downstream:auto;input:iterator<auto(T)>;output:iterator<auto(U)>) {
    var node=rx_state(keeper)
    var target=rx_state(downstream)
    unsafe {node.references++;target.references++}
    var handler <- @ capture(copy(node),copy(target)) (value:T) {
        var mapped:U
        var failed=false
        var message=""
        unsafe {
            try {mapped=invoke(node.data.selector,value)} recover {failed=true;message="{this_context().last_exception}"}
        }
        if(failed) {rx_terminal_state(target,true,message)} else {rx_next_state(target,mapped)}
    } finally {rx_finalize($ {rx_release_state(target);rx_release_state(node)})}
    return <- handler
}
def rx_connect(source:tuple<tag:RxMapTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) {
    var state=rx_state(source)
    unsafe {
        var handler <- rx_map_handler(source,observer,state.data.source.element,source.element)
        var inscope inner <- rx_forward(observer,handler)
        rx_connect_inner(state.data.source,inner)
    }
}
def private rx_filter_handler(keeper:auto;downstream:auto;input:iterator<auto(T)>) {
    var node=rx_state(keeper)
    var target=rx_state(downstream)
    unsafe {node.references++;target.references++}
    var handler <- @ capture(copy(node),copy(target)) (value:T) {
        var accepted=false
        var failed=false
        var message=""
        unsafe {
            try {accepted=invoke(node.data.predicate,value)} recover {failed=true;message="{this_context().last_exception}"}
        }
        if(failed) {rx_terminal_state(target,true,message)} elif(accepted) {rx_next_state(target,value)}
    } finally {rx_finalize($ {rx_release_state(target);rx_release_state(node)})}
    return <- handler
}
def rx_connect(source:tuple<tag:RxFilterTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) {
    var state=rx_state(source)
    unsafe {
        var handler <- rx_filter_handler(source,observer,source.element)
        var inscope inner <- rx_forward(observer,handler)
        rx_connect_inner(state.data.source,inner)
    }
}
def private rx_take_handler(downstream:auto;limit:int;input:iterator<auto(T)>) {
    var count=0
    var target=rx_state(downstream)
    unsafe {target.references++}
    var handler <- @ capture(copy(target),copy(limit),copy(count)) (value:T) {
        count++
        rx_next_state(target,value)
        if(count>=limit) {rx_terminal_state(target,false)}
    } finally {rx_finalize($ {rx_release_state(target)})}
    return <- handler
}
def rx_connect(source:tuple<tag:RxTakeTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) {
    var state=rx_state(source)
    unsafe {
        if(state.data.count==0) {rx_done(observer);return}
        var handler <- rx_take_handler(observer,state.data.count,source.element)
        var inscope inner <- rx_forward(observer,handler)
        rx_connect_inner(state.data.source,inner)
    }
}
def private rx_skip_handler(downstream:auto;remaining:int;input:iterator<auto(T)>) {
    var left=remaining
    var target=rx_state(downstream)
    unsafe {target.references++}
    var handler <- @ capture(copy(target),copy(left)) (value:T) {
        if(left>0) {left--;return}
        rx_next_state(target,value)
    } finally {rx_finalize($ {rx_release_state(target)})}
    return <- handler
}

def rx_connect(source:tuple<tag:RxSkipTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) {
    unsafe {
        var handler <- rx_skip_handler(observer,rx_state(source).data.count,source.element)
        var inscope inner <- rx_forward(observer,handler)
        rx_connect_inner(rx_state(source).data.source,inner)
    }
}

def private rx_while_handler(keeper:auto;downstream:auto;input:iterator<auto(T)>;skip:bool) {
    var skipping=true
    var node=rx_state(keeper)
    var target=rx_state(downstream)
    unsafe {node.references++;target.references++}
    var handler <- @ capture(copy(node),copy(target),copy(skip),copy(skipping)) (value:T) {
        if(skip && !skipping) {rx_next_state(target,value);return}
        var accepted=false;var failed=false;var message=""
        unsafe {try {accepted=invoke(node.data.predicate,value)} recover {failed=true;message="{this_context().last_exception}"}}
        if(failed) {rx_terminal_state(target,true,message);return}
        if(skip) {
            if(!accepted) {skipping=false;rx_next_state(target,value)}
        } elif(accepted) {rx_next_state(target,value)}
        else {rx_terminal_state(target,false)}
    } finally {rx_finalize($ {rx_release_state(target);rx_release_state(node)})}
    return <- handler
}

def private rx_while_connect(source:auto;observer:auto;skip:bool) {
    var handler <- rx_while_handler(source,observer,source.element,skip)
    var inscope inner <- rx_forward(observer,handler)
    unsafe {rx_connect_inner(rx_state(source).data.source,inner)}
}

def rx_connect(source:tuple<tag:RxTakeWhileTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) {rx_while_connect(source,observer,false)}
def rx_connect(source:tuple<tag:RxSkipWhileTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) {rx_while_connect(source,observer,true)}

def private rx_pairwise_handler(downstream:auto;input:iterator<auto(T)>) {
    var previous:T -const -&
    var seen=false
    var target=rx_state(downstream)
    unsafe {target.references++}
    var handler <- @ capture(copy(target),copy(previous),copy(seen)) (value:T) {
        var current:T -const -&
        static_if(typeinfo is_string(type<T>)) {current=clone_string(value)} else {current=value}
        var pair=(previous=previous,current=current)
        let emit=seen
        // Commit history before downstream code can reenter the producer.
        previous=current;seen=true
        if(emit) {rx_next_state(target,pair)}
    } finally {rx_finalize($ {rx_release_state(target)})}
    return <- handler
}

def rx_connect(source:tuple<tag:RxPairwiseTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) {
    var handler <- rx_pairwise_handler(observer,rx_state(source).data.source.element)
    var inscope inner <- rx_forward(observer,handler)
    unsafe {rx_connect_inner(rx_state(source).data.source,inner)}
}

def rx_connect(source:tuple<tag:RxFinallyTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) {
    var keeper <- rx_ref(source)
    var action <- @ capture(<-keeper) () {unsafe {invoke(rx_state(keeper).data.action)}} finally {rx_finalize($ {delete keeper})}
    var failed=false;var message=""
    unsafe {
        // Attach after connect so synchronous terminal/late upstream cleanup
        // precedes finally. A failed connect must still attach/run the action.
        try {rx_connect(rx_state(source).data.source,observer)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {try {rx_unsubscribe(rx_state(observer).control)} recover {}}
        try {rx_add_cleanup(rx_state(observer).control,action)} recover {
            if(!failed) {failed=true;message="{this_context().last_exception}"}
        }
    }
    if(failed) {panic(message)}
}

def rx_connect(source:tuple<tag:RxDeferTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) {
    var state=rx_state(source)
    unsafe {
        var inscope child:typedecl(invoke(state.data.factory)) -const -&
        var failed=false
        var message=""
        try {child <- invoke(state.data.factory)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {rx_error(observer,message);return}
        var failure=""
        var connectFailed=false
        try {rx_connect(child,observer)} recover {failure="{this_context().last_exception}";connectFailed=true}
        delete child
        if(connectFailed) {panic(failure)}
    }
}

// A hot broadcast source. Reentrant notifications are queued, never nested.
def private rx_subject_storage(unused:type<auto(T)>;mode,capacity:int) {
    var marker <- rx_observer_marker(type<T>)
    var slots:array<tuple<id:uint64;observer:typedecl(marker) -const -&>>
    var snapshot:array<typedecl(rx_state(marker)) -const -&>
    var replay_buffers:array<array<T -const -&>>
    var queue:array<tuple<kind:int;value:T -const -&;error:string>>
    var history:array<T -const -&>
    var timestamps:array<int64>
    var clock:RxScheduler
    return <- rx_node(RxSubjectTag(),(slots <- slots,snapshot <- snapshot,replay_buffers <- replay_buffers,queue <- queue,history <- history,timestamps <- timestamps,clock <- clock,window_ms=0l,mode=mode,capacity=capacity,
        serial=uint64(0),dispatching=false,stopped=false,terminated=false,failed=false,error=""),type<T>)
}
def rx_subject(unused:type<auto(T)>) {return <- rx_subject_storage(type<T>,0,0)}
def rx_behavior_subject(initial:auto(BehaviorValue)) {
    var source <- rx_subject_storage(type<BehaviorValue>,1,1)
    unsafe {
        static_if(typeinfo is_string(type<BehaviorValue>)) {rx_state(source).data.history |> push(clone_string(initial))}
        else {rx_state(source).data.history |> push(initial)}
    }
    return <- source
}
def rx_replay_subject(unused:type<auto(ReplayValue)>;buffer_size:int) {
    if(buffer_size<=0) {panic("rx_replay_subject: buffer_size must be positive")}
    return <- rx_subject_storage(type<ReplayValue>,2,buffer_size)
}
def rx_replay_subject(unused:type<auto(TimedValue)>;buffer_size:int;window_ms:int|int64;scheduler:RxScheduler) {
    if(buffer_size<=0 || window_ms<=0) {panic("rx_replay_subject: capacity and window must be positive")}
    var subject <- rx_subject_storage(type<TimedValue>,2,buffer_size)
    unsafe {rx_state(subject).data.window_ms=int64(window_ms);rx_state(subject).data.clock <- rx_scheduler_clone(scheduler)}
    return <- subject
}

def private rx_subject_prune(source:auto) : void {
    rx_subject_prune_state(rx_state(source))
}

def private rx_subject_prune_state(var state:auto?) : void {
    unsafe {
        if(state.data.window_ms==0) {return}
        let now=rx_now_ms(state.data.clock)
        while(!empty(state.data.timestamps) && now-state.data.timestamps[0]>=state.data.window_ms) {
            state.data.timestamps |> erase(0)
            rx_queue_drop_first(state.data.history)
        }
    }
}

def rx_behavior_value(source:tuple<tag:RxSubjectTag;owner:iterator<auto?>;element:iterator<auto(BehaviorStored)>>) : BehaviorStored {
    unsafe {
        let state=rx_state(source)
        if(state.data.mode!=1) {panic("rx_behavior_value: requires a BehaviorSubject")}
        if(state.data.terminated && state.data.failed) {panic(state.data.error)}
        return state.data.history[0]
    }
}
def rx_subject_buffered_count(source:tuple<tag:RxSubjectTag;owner:iterator<auto?>;element:iterator<auto>>) : int {
    var retained <- rx_ref(source)
    var count=0
    var failed=false;var message=""
    try {rx_subject_prune(retained);unsafe {count=length(rx_state(retained).data.history)}} recover {failed=true;message="{this_context().last_exception}"}
    delete retained
    if(failed) {panic(message)}
    return count
}
def private rx_subject_remember_state(var state:auto?;value:auto(SavedValue)) {
    unsafe {
        if(state.data.mode==0) {return}
        rx_subject_prune_state(state)
        state.data.history |> push(value)
        if(state.data.window_ms>0) {state.data.timestamps |> push(rx_now_ms(state.data.clock))}
        if(length(state.data.history)>state.data.capacity) {
            var removed <- state.data.history[0]
            state.data.history |> erase(0)
            if(state.data.window_ms>0) {state.data.timestamps |> erase(0)}
            static_if(typeinfo can_delete(type<SavedValue>)) {delete removed}
        }
    }
}
def private rx_remove(source:auto;id:uint64) {
    var state=rx_state(source)
    unsafe {
        for(i in range(length(state.data.slots))) {
            if(state.data.slots[i].id==id) {
                // Remove before finalizing callbacks: their cleanup may emit
                // or unsubscribe another listener on the same Subject.
                var removed <- state.data.slots[i]
                state.data.slots |> erase(i)
                rx_finalize($ {delete removed})
                break
            }
        }
    }
}
def rx_subscriber_count(source:tuple<tag:RxSubjectTag;owner:iterator<auto?>;element:iterator<auto>>) : int {
    unsafe {return length(rx_state(source).data.slots)}
}
def rx_connect(source:tuple<tag:RxSubjectTag;owner:iterator<auto?>;element:iterator<auto(SubjectValue)>>;observer:auto) {
    var state=rx_state(source)
    unsafe {
        if(state.data.mode==0 && state.data.stopped) {
            rx_terminal(observer,state.data.failed,state.data.error)
            return
        }
        if(!state.data.terminated) {
            state.data.serial++
            let id=state.data.serial
            state.data.slots |> emplace((id=id,observer <- rx_ref(observer)))
            var keeper <- rx_ref(source)
            var cleanup <- @ capture(<-keeper,copy(id)) () {rx_remove(keeper,id)} finally {rx_finalize($ {delete keeper})}
            rx_add_cleanup(rx_state(observer).control,cleanup)
        }
        if(state.data.mode==0) {return}
        // Pause live dispatch while replaying a snapshot. Reentrant next and
        // terminal events queue behind the entire replay, including when a new
        // subscriber is added from an already active broadcast callback.
        let wasDispatching=state.data.dispatching
        state.data.dispatching=true
        var snapshot:array<SubjectValue>
        var cacheSnapshot=false
        var fromPool=false
        var replayCount=0
        let historyLocks=lock_count(state.data.history)
        var failed=false;var message=""
        try {
            rx_subject_prune(source)
            if(state.data.mode==2 || !state.data.terminated) {
                // Reuse only an empty POD buffer. Always invoke array clone:
                // users may override it even for POD arrays. Nested replay
                // takes a different buffer, and timed pruning cannot alter it.
                static_if(typeinfo is_pod(type<SubjectValue>) && !typeinfo can_delete(type<SubjectValue>)) {
                    cacheSnapshot=true
                    if(!empty(state.data.replay_buffers)) {
                        let last=length(state.data.replay_buffers)-1
                        snapshot <- state.data.replay_buffers[last]
                        state.data.replay_buffers |> erase(last)
                        fromPool=true
                    }
                }
                snapshot := state.data.history
                replayCount=length(snapshot)
            }
            // A native array iterator can stay locked after a callback panic.
            var replayIndex=0
            while(replayIndex<replayCount && !rx_stopped(observer)) {
                rx_next(observer,snapshot[replayIndex])
                replayIndex++
            }
            if(state.data.terminated) {rx_terminal(observer,state.data.failed,state.data.error)}
        } recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {
            // Native array clone uses foreach; a throwing clone hook can leave
            // both arrays locked. Its frames have unwound. Preserve any lock
            // held by an outer replay/clone, and release only this call's locks.
            while(lock_count(state.data.history)>historyLocks) {__builtin_array_unlock(state.data.history)}
            while(lock_count(snapshot)>0) {__builtin_array_unlock(snapshot)}
        }
        try {
            if(cacheSnapshot && (fromPool || length(snapshot)>0)) {
                // No finalizers/GC references in POD payloads. Clear the length
                // before caching; do not retain replay values or invoke hooks.
                __builtin_array_clear(snapshot)
                state.data.replay_buffers |> emplace(snapshot)
            } else {delete snapshot}
        } recover {
            if(!failed) {failed=true;message="{this_context().last_exception}"}
            try {delete snapshot} recover {}
        }
        state.data.dispatching=wasDispatching
        if(!wasDispatching) {
            try {rx_subject_drain(source)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        }
        if(failed) {panic(message)}
    }
}
def private rx_subject_drain(source:auto) {rx_subject_drain_state(rx_state(source))}

def private rx_subject_drain_state(var state:auto?) {
    unsafe {
        if(state.data.dispatching) {return}
        state.data.dispatching=true
        var failure=""
        var failed=false
        while(!empty(state.data.queue)) {
            let event=state.data.queue[0]
            state.data.queue |> erase(0)
            if(event.kind==0) {
                try {rx_subject_remember_state(state,event.value)} recover {if(!failed) {failure="{this_context().last_exception}";failed=true}}
            } else {state.data.terminated=true}
            // The previous delivery has released every snapshot pin before
            // returning here. Nested sends only append to the FIFO queue.
            if(event.kind==0 && !typeinfo can_delete(type<typedecl(event.value) -const -&>)) {
                try {rx_subject_broadcast_state(state,event.value)} recover {if(!failed) {failure="{this_context().last_exception}";failed=true}}
            } else {
                var inscope observers:array<typedecl(state.data.slots[0].observer) -const -&>
                for(slot in state.data.slots) {observers |> emplace(rx_ref(slot.observer))}
                for(observer in observers) {
                    try {
                        if(event.kind==0) {rx_next(observer,event.value)}
                        else {rx_terminal(observer,event.kind==2,event.error)}
                    } recover {if(!failed) {failure="{this_context().last_exception}";failed=true}}
                }
            }
        }
        state.data.dispatching=false
        if(failed) {panic(failure)}
    }
}
// Only used while dispatching is true: nested sends queue behind this snapshot.
// Entries are nulled before releasing their pins, including when callbacks fail.
def private rx_subject_broadcast_state(var state:auto?;value:auto) {
    var held=0
    var failed=false;var failure=""
    unsafe {
        try {
            let count=length(state.data.slots)
            resize(state.data.snapshot,count)
            while(held<count) {
                var observer=rx_state(state.data.slots[held].observer)
                observer.references++
                state.data.snapshot[held]=observer
                held++
            }
            var index=0
            while(index<held) {
                try {rx_next_state(state.data.snapshot[index],value)} recover {if(!failed) {failed=true;failure="{this_context().last_exception}"}}
                index++
            }
        } recover {if(!failed) {failed=true;failure="{this_context().last_exception}"}}
        var index=0
        while(index<held) {
            var observer=state.data.snapshot[index]
            state.data.snapshot[index]=null
            try {rx_release_state(observer)} recover {if(!failed) {failed=true;failure="{this_context().last_exception}"}}
            index++
        }
    }
    if(failed) {panic(failure)}
}

def rx_subject_next(source:tuple<tag:RxSubjectTag;owner:iterator<auto?>;element:iterator<auto(T)>>;value:T) {
    var state=rx_state(source)
    unsafe {if(state.data.stopped) {return}}
    // A plain Subject does not need an event queue entry for a nonrecursive
    // send. Its snapshot storage is reused. Pin states before user callbacks:
    // may remove the listener, delete the publisher or enqueue more events.
    unsafe {state.references++}
    var failure=""
    var failed=false
    try {unsafe {
        if(!state.data.dispatching && state.data.mode==0 && !typeinfo can_delete(type<T>)) {
            var current=value
            static_if(typeinfo is_string(type<T>)) {current=clone_string(value)}
            state.data.dispatching=true
            if(length(state.data.slots)==1) {
                var listener=rx_state(state.data.slots[0].observer)
                listener.references++
                try {rx_next_state(listener,current)} recover {failure="{this_context().last_exception}";failed=true}
                try {rx_release_state(listener)} recover {if(!failed) {failure="{this_context().last_exception}";failed=true}}
            } else {
                try {rx_subject_broadcast_state(state,current)} recover {failure="{this_context().last_exception}";failed=true}
            }
            state.data.dispatching=false
        } else {
            static_if(typeinfo is_string(type<T>)) {state.data.queue |> push((kind=0,value=clone_string(value),error=""))}
            else {state.data.queue |> push((kind=0,value=value,error=""))}
        }
    }} recover {if(!failed) {failure="{this_context().last_exception}";failed=true}}
    try {rx_subject_drain_state(state)} recover {if(!failed) {failure="{this_context().last_exception}";failed=true}}
    try {rx_release_state(state)} recover {if(!failed) {failure="{this_context().last_exception}";failed=true}}
    if(failed) {panic(failure)}
}
def private rx_subject_end(source:auto;isError:bool;message:string) {
    var state=rx_state(source)
    unsafe {
        if(state.data.stopped) {return}
        state.data.stopped=true
        state.data.failed=isError
        state.data.error=clone_string(message)
        var event:typedecl(state.data.queue[0]) -const -&
        event.kind=isError ? 2 : 1
        event.error=state.data.error
        state.data.queue |> push(event)
    }
    var inscope retained <- rx_ref(source)
    var failure=""
    var failed=false
    try {rx_subject_drain(retained)} recover {failure="{this_context().last_exception}";failed=true}
    delete retained
    if(failed) {panic(failure)}
}
def rx_subject_complete(source:tuple<tag:RxSubjectTag;owner:iterator<auto?>;element:iterator<auto>>) {rx_subject_end(source,false,"")}
def rx_subject_error(source:tuple<tag:RxSubjectTag;owner:iterator<auto?>;element:iterator<auto>>;message:string) {rx_subject_end(source,true,message)}

struct RxShareOptions {
    reset_on_error:bool=true
    reset_on_complete:bool=true
    reset_on_refcount_zero:bool=true
}
struct RxShareTag {_marker:uint8}
struct RxShareSessionTag {_marker:uint8}

def private rx_share_session(unused:type<auto(SharedItem)>;buffer_size:int;id:uint64) {
    return <- rx_node(RxShareSessionTag(),(subject <- rx_subject_storage(type<SharedItem>,buffer_size>0 ? 2 : 0,buffer_size),
        upstream <- rx_subscription(),id=id,listeners=0,connected=false,cancelled=false,ended=0),type<SharedItem>)
}
def private rx_share_node(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(SharedItem)>>;buffer_size:int;settings:RxShareOptions=RxShareOptions()) {
    var current:typedecl(rx_share_session(type<SharedItem>,buffer_size,uint64(0))) -const -&
    return <- rx_node(RxShareTag(),(source <- source,current <- current,buffer_size=buffer_size,reset_error=settings.reset_on_error,reset_complete=settings.reset_on_complete,reset_zero=settings.reset_on_refcount_zero,closed=false,window_ms=0l,clock <- default<RxScheduler>,serial=uint64(0),busy=0,pumping=false),type<SharedItem>)
}
def rx_share(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>) {return <- rx_share_node(source,0)}
def rx_share_replay(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;buffer_size:int=1) {
    if(buffer_size<=0) {panic("rx_share_replay: buffer_size must be positive")}
    return <- rx_share_node(source,buffer_size,RxShareOptions(reset_on_complete=false))
}
def rx_share(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;settings:RxShareOptions) {return <- rx_share_node(source,0,settings)}

def rx_share_replay(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;buffer_size:int;settings:RxShareOptions) {
    if(buffer_size<=0) {delete source;panic("rx_share_replay: buffer_size must be positive")}
    return <- rx_share_node(source,buffer_size,settings)
}

def rx_share_replay(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;buffer_size:int;window_ms:int|int64;scheduler:RxScheduler;settings:RxShareOptions=RxShareOptions(reset_on_complete=false)) {
    if(buffer_size<=0 || window_ms<=0) {delete source;panic("rx_share_replay: capacity and window must be positive")}
    var hub <- rx_share_node(source,buffer_size,settings)
    unsafe {rx_state(hub).data.window_ms=int64(window_ms);rx_state(hub).data.clock <- rx_scheduler_clone(scheduler)}
    return <- hub
}

def private rx_share_detach(hub,session:auto) : void {
    unsafe {
        let state=rx_state(hub)
        if(!empty(state.data.current.owner) && rx_state(state.data.current).data.id==rx_state(session).data.id) {
            var old <- state.data.current
            delete old
        }
    }
}
def private rx_share_disconnect(hub,session:auto) : void {
    unsafe {
        rx_state(session).data.cancelled=true
        rx_share_detach(hub,session)
        rx_unsubscribe(rx_state(session).data.upstream)
        rx_cleanup(rx_control(rx_state(session).data.upstream))
    }
}
def private rx_share_release(hub,session:auto) : void {
    unsafe {
        let state=rx_state(hub);let group=rx_state(session)
        group.data.listeners--
        if(group.data.listeners!=0 || group.data.ended!=0 || group.data.cancelled || !state.data.reset_zero) {return}
        state.data.busy++
        var failed=false;var message=""
        try {rx_share_disconnect(hub,session)} recover {failed=true;message="{this_context().last_exception}"}
        state.data.busy--
        try {rx_share_pump(hub)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        if(failed) {panic(message)}
    }
}
// A native failure cannot leave subscribers waiting on a dead upstream.
// Close the whole failed generation without manufacturing an on_error event.
def private rx_share_abort(hub,session:auto) : void {
    unsafe {
        let state=rx_state(hub);let group=rx_state(session)
        state.data.busy++
        try {rx_share_disconnect(hub,session)} recover {}
        var subject=rx_state(group.data.subject)
        var observers:array<typedecl(subject.data.slots[0].observer) -const -&>
        for(slot in subject.data.slots) {observers |> emplace(rx_ref(slot.observer))}
        for(observer in observers) {
            try {rx_unsubscribe(rx_state(observer).control)} recover {}
        }
        delete observers
        state.data.busy--
    }
}
def private rx_share_next(hub,session:auto;value:auto) : void {
    unsafe {
        let state=rx_state(hub);let group=rx_state(session)
        if(group.data.cancelled || group.data.ended!=0) {return}
        state.data.busy++
        var failed=false;var message=""
        try {rx_subject_next(group.data.subject,value)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {rx_share_abort(hub,session)}
        state.data.busy--
        try {rx_share_pump(hub)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        if(failed) {panic(message)}
    }
}
def private rx_share_terminal(hub,session:auto;error:bool;message:string="") : void {
    unsafe {
        let state=rx_state(hub);let group=rx_state(session)
        if(group.data.cancelled || group.data.ended!=0) {return}
        group.data.ended=error ? 1 : 2
        state.data.busy++
        if((error && state.data.reset_error) || (!error && state.data.reset_complete)) {rx_share_detach(hub,session)}
        var failed=false;var failure=""
        // Registered producer cleanup precedes terminal fan-out. Reconnection
        // is postponed until this fan-out AND an active sync connect unwind.
        try {rx_cleanup(rx_control(group.data.upstream))} recover {failed=true;failure="{this_context().last_exception}"}
        try {rx_subject_end(group.data.subject,error,message)} recover {if(!failed) {failed=true;failure="{this_context().last_exception}"}}
        state.data.busy--
        if(failed) {rx_share_abort(hub,session)}
        try {rx_share_pump(hub)} recover {if(!failed) {failed=true;failure="{this_context().last_exception}"}}
        if(failed) {panic(failure)}
    }
}
def private rx_share_start(hub,session:auto;input:iterator<auto(SharedValue)>) : void {
    var values <- rx_ref(hub);var valueGroup <- rx_ref(session)
    var errors <- rx_ref(hub);var errorGroup <- rx_ref(session)
    var completed <- rx_ref(hub);var doneGroup <- rx_ref(session)
    var on_next <- @ capture(<-values,<-valueGroup) (value:SharedValue) {rx_share_next(values,valueGroup,value)} finally {rx_finalize($ {delete values;delete valueGroup})}
    var on_error <- @ capture(<-errors,<-errorGroup) (message:string) {rx_share_terminal(errors,errorGroup,true,message)} finally {rx_finalize($ {delete errors;delete errorGroup})}
    var on_complete <- @ capture(<-completed,<-doneGroup) () {rx_share_terminal(completed,doneGroup,false)} finally {rx_finalize($ {delete completed;delete doneGroup})}
    unsafe {rx_subscribe_with(rx_state(session).data.upstream,rx_state(hub).data.source,on_next,on_error,on_complete)}
}
def private rx_share_pump(hub:auto) : void {
    unsafe {
        let state=rx_state(hub)
        if(state.data.closed || state.data.pumping || state.data.busy!=0) {return}
        state.data.pumping=true
        var failed=false;var message=""
        while(!empty(state.data.current.owner)) {
            var session <- rx_ref(state.data.current)
            let group=rx_state(session)
            if(group.data.connected || group.data.cancelled || group.data.ended!=0 || group.data.listeners==0) {delete session;break}
            group.data.connected=true
            state.data.busy++
            var startFailed=false;var failure=""
            try {rx_share_start(hub,session,hub.element)} recover {startFailed=true;failure="{this_context().last_exception}"}
            if(startFailed) {
                rx_share_abort(hub,session)
                if(!failed) {failed=true;message=failure}
            }
            state.data.busy--
            delete session
            // A reentrant subscriber may have installed the next generation.
            // Start it iteratively, including after an old generation failed.
        }
        state.data.pumping=false
        if(failed) {panic(message)}
    }
}
def rx_connect(hub:tuple<tag:RxShareTag;owner:iterator<auto?>;element:iterator<auto(ShareInput)>>;observer:auto) : void {
    unsafe {
        let state=rx_state(hub)
        if(state.data.closed) {rx_done(observer);return}
        if(empty(state.data.current.owner)) {
            state.data.serial++
            state.data.current <- rx_share_session(type<ShareInput>,state.data.buffer_size,state.data.serial)
            if(state.data.window_ms>0) {
                let cache=rx_state(rx_state(state.data.current).data.subject)
                cache.data.window_ms=state.data.window_ms
                cache.data.clock <- rx_scheduler_clone(state.data.clock)
            }
        }
        var session <- rx_ref(state.data.current)
        rx_state(session).data.listeners++
        var keeper <- rx_ref(hub);var listener <- rx_ref(session)
        var cleanup <- @ capture(<-keeper,<-listener) () {rx_share_release(keeper,listener)} finally {rx_finalize($ {delete keeper;delete listener})}
        rx_add_cleanup(rx_state(observer).control,cleanup)
        var failed=false;var message=""
        state.data.busy++
        try {
            if(!rx_stopped(observer)) {rx_connect(rx_state(session).data.subject,observer)}
        } recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {try {rx_unsubscribe(rx_state(observer).control)} recover {}}
        state.data.busy--
        try {rx_share_pump(hub)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        delete session
        if(failed) {panic(message)}
    }
}

// A keep-alive hub must be closed explicitly before releasing its last view.
def private rx_share_close_retained(hub:tuple<tag:RxShareTag;owner:iterator<auto?>;element:iterator<auto>>) {
    unsafe {
        let state=rx_state(hub)
        if(state.data.closed) {return}
        state.data.closed=true
        if(empty(state.data.current.owner)) {return}
        var session <- rx_ref(state.data.current)
        var failed=false;var message=""
        try {rx_share_disconnect(hub,session)} recover {failed=true;message="{this_context().last_exception}"}
        let subject=rx_state(rx_state(session).data.subject)
        var observers:array<typedecl(subject.data.slots[0].observer) -const -&>
        for(slot in subject.data.slots) {observers |> emplace(rx_ref(slot.observer))}
        var index=0
        while(index<length(observers)) {
            try {rx_unsubscribe(rx_state(observers[index]).control)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
            index++
        }
        delete observers;delete session
        if(failed) {panic(message)}
    }
}

def rx_share_close(hub:tuple<tag:RxShareTag;owner:iterator<auto?>;element:iterator<auto>>) {
    var retained <- rx_ref(hub)
    var failed=false;var message=""
    try {rx_share_close_retained(retained)} recover {failed=true;message="{this_context().last_exception}"}
    delete retained
    if(failed) {panic(message)}
}

// Explicit retained descriptor for fan-out pipelines. Each subscription has its
// own operator state; a Subject's broadcasts are shared by all retained views.
def rx_clone(source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>) {return <- rx_ref(source)}

// daScript exceptions require explicit destruction before rethrowing; inscope
// alone does not unwind these owned callback/descriptor frames on this SDK.
def private rx_connect_inner(source:auto;var observer:auto) {
    var failed=false
    var message=""
    try {rx_connect(source,observer)} recover {message="{this_context().last_exception}";failed=true}
    delete observer
    if(failed) {panic(message)}
}

struct RxMergeTag {_marker:uint8}
struct RxUntilTag {_marker:uint8}
struct RxUntilRunTag {_marker:uint8}
struct RxUntilSignalTag {_marker:uint8}
struct RxUntilValueTag {_marker:uint8}

def rx_take_until(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(UntilValue)>>;
    var notifier:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>) {
    if(empty(source.owner) || empty(notifier.owner)) {panic("rx_take_until: source was moved or deleted")}
    var first <- source
    if(empty(notifier.owner)) {delete first;panic("rx_take_until: use rx_clone to pass the same source twice")}
    return <- rx_node(RxUntilTag(),(source <- first,notifier <- notifier),type<UntilValue>)
}

def private rx_until_cancel(run:auto) : void {
    unsafe {
        var state=rx_state(run)
        state.data.stopped=true
        state.data.pending_terminal=0
        delete state.data.queue
        var failed=false;var message=""
        try {rx_unsubscribe(state.data.input);rx_cleanup(rx_control(state.data.input))} recover {failed=true;message="{this_context().last_exception}"}
        try {rx_unsubscribe(state.data.signal);rx_cleanup(rx_control(state.data.signal))} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        if(failed) {panic(message)}
    }
}
def private rx_until_stop(run:auto;error:bool;message:string="") : void {
    unsafe {
        var state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        // Stop producers before user terminal callbacks, including reentrant
        // notifications. Preserve earlier values on completion, drop on error.
        var pending <- state.data.queue
        var failed=false;var failure=""
        try {rx_until_cancel(run)} recover {failed=true;failure="{this_context().last_exception}"}
        if(failed && !error) {
            delete pending
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(failure)
        }
        if(!error) {state.data.queue <- pending}
        delete pending
        if(state.data.connecting!=0) {
            state.data.pending_terminal=error ? 1 : 2
            state.data.pending_error=string(message)
        } else {
            var event:typedecl(state.data.queue[0]) -const -&
            event.kind=error ? 1 : 2;event.error=string(message)
            state.data.queue |> push(event)
            rx_serial_drain(run)
        }
    }
}
def private rx_until_value(run:auto;value:auto;side:RxUntilSignalTag) : void {rx_until_stop(run,false)}
def private rx_until_value(run:auto;value:auto(UntilReceived);side:RxUntilValueTag) : void {
    unsafe {
        var state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        static_if(typeinfo is_string(type<UntilReceived>)) {state.data.queue |> push((kind=0,value=string(value),error=""))}
        else {state.data.queue |> push((kind=0,value=value,error=""))}
    }
    rx_serial_drain(run)
}
def private rx_until_start(run:auto;source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(UntilInput)>>;control:RxSubscription;side:auto;signal:bool) : void {
    unsafe {
        var state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        var values <- rx_ref(run);var errors <- rx_ref(run);var completed <- rx_ref(run)
        var on_next <- @ capture(<-values,copy(side)) (value:UntilInput) {rx_until_value(values,value,side)} finally {rx_finalize($ {delete values})}
        var on_error <- @ capture(<-errors) (message:string) {rx_until_stop(errors,true,message)} finally {rx_finalize($ {delete errors})}
        var on_complete <- @ capture(<-completed,copy(signal)) () {if(!signal) {rx_until_stop(completed,false)}} finally {rx_finalize($ {delete completed})}
        state.data.connecting++
        var failed=false;var message=""
        try {rx_subscribe_with(control,source,on_next,on_error,on_complete)} recover {failed=true;message="{this_context().last_exception}"}
        state.data.connecting--
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
        if(state.data.connecting==0 && state.data.pending_terminal!=0 && !rx_stopped(state.data.observer)) {
            var event:typedecl(state.data.queue[0]) -const -&
            event.kind=state.data.pending_terminal;event.error=state.data.pending_error
            state.data.pending_terminal=0
            state.data.queue |> push(event)
        }
        rx_serial_drain(run)
    }
}
def rx_connect(source:tuple<tag:RxUntilTag;owner:iterator<auto?>;element:iterator<auto(UntilOutput)>>;observer:auto) : void {
    var queue:array<tuple<kind:int;value:UntilOutput;error:string>>
    var run <- rx_node(RxUntilRunTag(),(source <- rx_ref(source),observer <- rx_ref(observer),
        input <- rx_subscription(),signal <- rx_subscription(),queue <- queue,stopped=false,dispatching=false,connecting=0,pending_terminal=0,pending_error=""),type<UntilOutput>)
    var keeper <- rx_ref(run)
    var cleanup <- @ capture(<-keeper) () {rx_until_cancel(keeper)} finally {rx_finalize($ {delete keeper})}
    var failed=false;var message=""
    unsafe {
        rx_add_cleanup(rx_state(observer).control,cleanup)
        var state=rx_state(run)
        var inputs=rx_state(source)
        try {
            // Register the stop signal before a synchronous producer can run.
            rx_until_start(run,inputs.data.notifier,state.data.signal,RxUntilSignalTag(),true)
            rx_until_start(run,inputs.data.source,state.data.input,RxUntilValueTag(),false)
        } recover {failed=true;message="{this_context().last_exception}"}
    }
    delete run
    if(failed) {panic(message)}
}

struct RxConcatTag {_marker:uint8}
struct RxJoinRunTag {_marker:uint8}

def rx_merge(var left:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;
    var right:tuple<tag:auto;owner:iterator<auto?>;element:iterator<T>>) {
    if(empty(left.owner) || empty(right.owner)) {panic("rx_merge: source was moved or deleted")}
    var first <- left
    if(empty(right.owner)) {delete first;panic("rx_merge: use rx_clone to pass the same source twice")}
    return <- rx_node(RxMergeTag(),(left <- first,right <- right),type<T>)
}
def rx_concat(var left:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;
    var right:tuple<tag:auto;owner:iterator<auto?>;element:iterator<T>>) {
    if(empty(left.owner) || empty(right.owner)) {panic("rx_concat: source was moved or deleted")}
    var first <- left
    if(empty(right.owner)) {delete first;panic("rx_concat: use rx_clone to pass the same source twice")}
    return <- rx_node(RxConcatTag(),(left <- first,right <- right),type<T>)
}

// A run owns two independent child controls. Register its cancellation on the
// parent before connecting either source, including synchronous sources.
def private rx_join_cancel(run:auto) : void {
    var state=rx_state(run)
    unsafe {
        state.data.stopped=true
        delete state.data.queue
        var failed=false
        var message=""
        try {rx_unsubscribe(state.data.left);rx_cleanup(rx_control(state.data.left))} recover {failed=true;message="{this_context().last_exception}"}
        try {rx_unsubscribe(state.data.right);rx_cleanup(rx_control(state.data.right))} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        if(failed) {panic(message)}
    }
}
def private rx_join_drain(run:auto) : void {
    var state=rx_state(run)
    unsafe {
        if(state.data.dispatching) {return}
        state.data.dispatching=true
        var failed=false
        var message=""
        try {
            while(!empty(state.data.queue) && !rx_stopped(state.data.observer)) {
                let event=state.data.queue[0]
                state.data.queue |> erase(0)
                if(event.kind==0) {rx_next(state.data.observer,event.value)}
                elif(event.kind==1) {rx_error(state.data.observer,event.error)}
                elif(state.data.concat && event.kind==2 && !state.data.right_started) {
                    // No user notification is active here. Resume delivery
                    // before connecting a synchronous right source, so take
                    // can stop that source on its very first value.
                    state.data.dispatching=false
                    rx_join_start(run,1)
                    return
                } elif(state.data.left_finished && state.data.right_finished) {
                    rx_done(state.data.observer)
                }
            }
        } recover {failed=true;message="{this_context().last_exception}"}
        state.data.dispatching=false
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
    }
}
def private rx_join_error(run:auto;message:string) : void {
    var state=rx_state(run)
    unsafe {
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        // Stop both inputs immediately, even when delivery must wait for the
        // current on_next to return. Preserve the source error over cleanup.
        try {rx_join_cancel(run)} recover {}
        var event:typedecl(state.data.queue[0]) -const -&
        event.kind=1;event.error=string(message)
        state.data.queue |> push(event)
    }
    rx_join_drain(run)
}
def private rx_join_finished(run:auto;side:int) : void {
    var state=rx_state(run)
    unsafe {
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        var failed=false
        var message=""
        // An async child's terminal callback precedes its normal cleanup.
        // Drain that cleanup now, before starting concat's next subscription.
        try {
            if(side==0) {rx_cleanup(rx_control(state.data.left))}
            else {rx_cleanup(rx_control(state.data.right))}
        } recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        if(side==0) {state.data.left_finished=true} else {state.data.right_finished=true}
        var event:typedecl(state.data.queue[0]) -const -&
        event.kind=side+2
        state.data.queue |> push(event)
    }
    rx_join_drain(run)
}
def private rx_join_start(run:tuple<tag:RxJoinRunTag;owner:iterator<auto?>;element:iterator<auto(T)>>;side:int) : void {
    var state=rx_state(run)
    unsafe {
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        if(side==0) {state.data.left_connecting=true}
        else {
            if(state.data.right_started) {return}
            state.data.right_started=true;state.data.right_connecting=true
        }
        var values <- rx_ref(run)
        var errors <- rx_ref(run)
        var completed <- rx_ref(run)
        var on_next <- @ capture(<-values) (value:T) {
            var target=rx_state(values)
            unsafe {
                if(target.data.stopped || rx_stopped(target.data.observer)) {return}
                target.data.queue |> push((kind=0,value=value,error=""))
            }
            rx_join_drain(values)
        } finally {rx_finalize($ {delete values})}
        var on_error <- @ capture(<-errors) (message:string) {rx_join_error(errors,message)} finally {rx_finalize($ {delete errors})}
        var on_complete <- @ capture(<-completed,copy(side)) () {
            var target=rx_state(completed)
            unsafe {
                if(side==0) {
                    target.data.left_done=true
                    if(!target.data.left_connecting) {rx_join_finished(completed,side)}
                } else {
                    target.data.right_done=true
                    if(!target.data.right_connecting) {rx_join_finished(completed,side)}
                }
            }
        } finally {rx_finalize($ {delete completed})}
        var failed=false
        var message=""
        try {
            if(side==0) {rx_subscribe_with(state.data.left,rx_state(state.data.source).data.left,on_next,on_error,on_complete)}
            else {rx_subscribe_with(state.data.right,rx_state(state.data.source).data.right,on_next,on_error,on_complete)}
        } recover {failed=true;message="{this_context().last_exception}"}
        if(side==0) {state.data.left_connecting=false} else {state.data.right_connecting=false}
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
        // Synchronous completion is advanced after connect's owned frames and
        // late-registered cleanup have unwound, never from inside its callback.
        if((side==0 && state.data.left_done) || (side==1 && state.data.right_done)) {rx_join_finished(run,side)}
    }
}
def private rx_join_connect(source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;observer:auto;concat:bool) : void {
    var queue:array<tuple<kind:int;value:T;error:string>>
    var run <- rx_node(RxJoinRunTag(),(source <- rx_ref(source),observer <- rx_ref(observer),
        left <- rx_subscription(),right <- rx_subscription(),queue <- queue,concat=concat,
        dispatching=false,stopped=false,left_connecting=false,right_connecting=false,
        left_done=false,right_done=false,left_finished=false,right_finished=false,right_started=false),type<T>)
    var keeper <- rx_ref(run)
    var cleanup <- @ capture(<-keeper) () {rx_join_cancel(keeper)} finally {rx_finalize($ {delete keeper})}
    unsafe {rx_add_cleanup(rx_state(observer).control,cleanup)}
    var failed=false
    var message=""
    try {
        rx_join_start(run,0)
        if(!concat) {rx_join_start(run,1)}
    } recover {failed=true;message="{this_context().last_exception}"}
    delete run
    if(failed) {panic(message)}
}
def rx_connect(source:tuple<tag:RxMergeTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {rx_join_connect(source,observer,false)}
def rx_connect(source:tuple<tag:RxConcatTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {rx_join_connect(source,observer,true)}

struct RxLatestTag {_marker:uint8}
struct RxWithLatestTag {_marker:uint8}
struct RxZipTag {_marker:uint8}
struct RxPairRunTag {_marker:uint8}
struct RxPairLeftTag {_marker:uint8}
struct RxPairRightTag {_marker:uint8}

def private rx_pair_node(tag:auto;var left:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(L)>>;
    var right:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(R)>>;queue_options:RxQueueOptions=RxQueueOptions()) {
    rx_queue_validate(queue_options)
    if(empty(left.owner) || empty(right.owner)) {panic("rx pair: source was moved or deleted")}
    var first <- left
    if(empty(right.owner)) {delete first;panic("rx pair: use rx_clone to pass the same source twice")}
    return <- rx_node(tag,(left <- first,right <- right,limits=RxQueueOptions(capacity=queue_options.capacity,policy=queue_options.policy)),type<tuple<first:L;second:R>>)
}
def rx_combine_latest(var left:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;
    var right:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>) {return <- rx_pair_node(RxLatestTag(),left,right)}
def rx_with_latest_from(var left:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;
    var right:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>) {return <- rx_pair_node(RxWithLatestTag(),left,right)}

def rx_zip(var left:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;
    var right:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>) {return <- rx_pair_node(RxZipTag(),left,right)}

def rx_zip(var left:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;
    var right:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;queue_options:RxQueueOptions) {return <- rx_pair_node(RxZipTag(),left,right,queue_options)}

def private rx_pair_cancel(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        state.data.stopped=true
        delete state.data.first
        delete state.data.second
    }
    rx_join_cancel(run)
}

// Serialized next/error/complete delivery shared by pair and flatten operators.
def private rx_serial_drain(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.dispatching) {return}
        state.data.dispatching=true
        var failed=false
        var message=""
        try {
            while(!empty(state.data.queue) && !rx_stopped(state.data.observer)) {
                var event <- state.data.queue[0]
                state.data.queue |> erase(0)
                var eventFailed=false;var eventMessage=""
                try {
                    if(event.kind==0) {rx_next(state.data.observer,event.value)}
                    elif(event.kind==1) {rx_error(state.data.observer,event.error)}
                    else {rx_done(state.data.observer)}
                } recover {eventFailed=true;eventMessage="{this_context().last_exception}"}
                try {
                    static_if(typeinfo is_array(type<typedecl(event.value) -const -&>)) {
                        // A native foreach can leave its array lock on panic.
                        // This uniquely owned batch is borrowed only during the
                        // callback: every consumer frame has now returned/unwound.
                        while(lock_count(event.value)>0) {__builtin_array_unlock(event.value)}
                    }
                    rx_queue_dispose(event)
                } recover {if(!eventFailed) {eventFailed=true;eventMessage="{this_context().last_exception}"}}
                if(eventFailed) {panic(eventMessage)}
            }
        } recover {failed=true;message="{this_context().last_exception}"}
        state.data.dispatching=false
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
    }
}

def private rx_pair_error(run:auto;message:string) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        try {rx_pair_cancel(run)} recover {}
        var event:typedecl(state.data.queue[0]) -const -&
        event.kind=1;event.error=string(message)
        state.data.queue |> push(event)
    }
    rx_serial_drain(run)
}

def private rx_pair_check_end(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        let exhausted=(state.data.left_finished && empty(state.data.first)) || (state.data.right_finished && empty(state.data.second))
        if((state.data.primary_only && state.data.left_finished) || (!state.data.primary_only && (exhausted || (!state.data.zip && state.data.left_finished && state.data.right_finished)))) {
            // Completion follows already queued pairs; an error discards them.
            var pending <- state.data.queue
            var failed=false
            var message=""
            try {rx_pair_cancel(run)} recover {failed=true;message="{this_context().last_exception}"}
            state.data.queue <- pending
            if(failed) {
                try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
                panic(message)
            }
            state.data.left_finished=true;state.data.right_finished=true
            var event:typedecl(state.data.queue[0]) -const -&
            event.kind=2
            state.data.queue |> push(event)
        }
    }
    rx_serial_drain(run)
}

def private rx_pair_emit(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        if(!empty(state.data.first) && !empty(state.data.second)) {
            // Snapshot at arrival, before a reentrant update can change latest.
            state.data.queue |> push((kind=0,value=(first=state.data.first[0],second=state.data.second[0]),error=""))
            if(state.data.zip) {
                // Detach both unmatched values before a payload finalizer can
                // reenter; neither value may be paired a second time.
                var first <- state.data.first[0];var second <- state.data.second[0]
                state.data.first |> erase(0);state.data.second |> erase(0)
                var failed=false;var message=""
                try {rx_queue_dispose(first)} recover {failed=true;message="{this_context().last_exception}"}
                try {rx_queue_dispose(second)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
                if(failed) {panic(message)}
            }
        }
    }
    rx_pair_check_end(run)
}
def private rx_pair_push(run:auto;value:auto;side:RxPairLeftTag) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        if(!state.data.zip) {clear(state.data.first)}
        while(state.data.zip && rx_queue_full(length(state.data.first),state.data.limits)) {
            if(state.data.limits.policy==RxOverflowPolicy.error) {rx_pair_error(run,"rx_zip: queue overflow");return}
            if(state.data.limits.policy==RxOverflowPolicy.drop_latest) {return}
            rx_queue_drop_first(state.data.first)
            if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        }
        static_if(typeinfo is_string(type<typedecl(value) -const -&>)) {state.data.first |> push(clone_string(value))}
        else {state.data.first |> push(value)}
    }
    rx_pair_emit(run)
}
def private rx_pair_push(run:auto;value:auto;side:RxPairRightTag) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        if(!state.data.zip) {clear(state.data.second)}
        while(state.data.zip && rx_queue_full(length(state.data.second),state.data.limits)) {
            if(state.data.limits.policy==RxOverflowPolicy.error) {rx_pair_error(run,"rx_zip: queue overflow");return}
            if(state.data.limits.policy==RxOverflowPolicy.drop_latest) {return}
            rx_queue_drop_first(state.data.second)
            if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        }
        static_if(typeinfo is_string(type<typedecl(value) -const -&>)) {state.data.second |> push(clone_string(value))}
        else {state.data.second |> push(value)}
    }
    unsafe {if(!rx_state(run).data.primary_only) {rx_pair_emit(run)}}
}
def private rx_pair_finished(run:auto;left:bool) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        var failed=false
        var message=""
        try {
            if(left) {rx_cleanup(rx_control(state.data.left))}
            else {rx_cleanup(rx_control(state.data.right))}
        } recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
        if(left) {state.data.left_finished=true} else {state.data.right_finished=true}
    }
    rx_pair_check_end(run)
}
def private rx_pair_start(run:auto;source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(V)>>;
    control:RxSubscription;side:auto;left:bool) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        if(left) {state.data.left_connecting=true} else {state.data.right_connecting=true}
        var values <- rx_ref(run)
        var errors <- rx_ref(run)
        var completed <- rx_ref(run)
        var on_next <- @ capture(<-values,copy(side)) (value:V) {rx_pair_push(values,value,side)} finally {rx_finalize($ {delete values})}
        var on_error <- @ capture(<-errors) (message:string) {rx_pair_error(errors,message)} finally {rx_finalize($ {delete errors})}
        var on_complete <- @ capture(<-completed,copy(left)) () {
            unsafe {
                let target=rx_state(completed)
                if(left) {
                    target.data.left_done=true
                    if(!target.data.left_connecting) {rx_pair_finished(completed,left)}
                } else {
                    target.data.right_done=true
                    if(!target.data.right_connecting) {rx_pair_finished(completed,left)}
                }
            }
        } finally {rx_finalize($ {delete completed})}
        var failed=false
        var message=""
        try {rx_subscribe_with(control,source,on_next,on_error,on_complete)} recover {failed=true;message="{this_context().last_exception}"}
        if(left) {state.data.left_connecting=false} else {state.data.right_connecting=false}
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
        if((left && state.data.left_done) || (!left && state.data.right_done)) {rx_pair_finished(run,left)}
    }
}
def private rx_pair_connect(source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<tuple<first:auto(L);second:auto(R)>>>;observer:auto;zip:bool;primary_only:bool=false) : void {
    unsafe {
        let inputs=rx_state(source)
        var first:array<L>
        var second:array<R>
        var queue:array<tuple<kind:int;value:tuple<first:L;second:R>;error:string>>
        var run <- rx_node(RxPairRunTag(),(source <- rx_ref(source),observer <- rx_ref(observer),
            left <- rx_subscription(),right <- rx_subscription(),queue <- queue,first <- first,second <- second,
            limits=RxQueueOptions(capacity=inputs.data.limits.capacity,policy=inputs.data.limits.policy),zip=zip,primary_only=primary_only,dispatching=false,stopped=false,left_connecting=false,right_connecting=false,
            left_done=false,right_done=false,left_finished=false,right_finished=false),type<tuple<first:L;second:R>>)
        var keeper <- rx_ref(run)
        var cleanup <- @ capture(<-keeper) () {rx_pair_cancel(keeper)} finally {rx_finalize($ {delete keeper})}
        rx_add_cleanup(rx_state(observer).control,cleanup)
        var failed=false
        var message=""
        try {
            let state=rx_state(run)
            if(primary_only) {
                rx_pair_start(run,inputs.data.right,state.data.right,RxPairRightTag(),false)
                rx_pair_start(run,inputs.data.left,state.data.left,RxPairLeftTag(),true)
            } else {
                rx_pair_start(run,inputs.data.left,state.data.left,RxPairLeftTag(),true)
                rx_pair_start(run,inputs.data.right,state.data.right,RxPairRightTag(),false)
            }
        } recover {failed=true;message="{this_context().last_exception}"}
        delete run
        if(failed) {panic(message)}
    }
}
def rx_connect(source:tuple<tag:RxLatestTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {rx_pair_connect(source,observer,false)}
def rx_connect(source:tuple<tag:RxZipTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {rx_pair_connect(source,observer,true)}

def rx_connect(source:tuple<tag:RxWithLatestTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {rx_pair_connect(source,observer,false,true)}

struct RxSwitchMapTag {_marker:uint8}
struct RxFlatMapTag {_marker:uint8}
struct RxExhaustTag {_marker:uint8}
struct RxFlatRunTag {_marker:uint8}
struct RxFlatChildTag {_marker:uint8}
struct RxFlatChildState {
    control:RxSubscription
    id:uint64
    active:bool=true
    connecting:bool=true
    done:bool
}

def private rx_flat_node(tag:auto;var source:auto;var selector:auto;
    marker:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(U)>>;max_active:int=0;queue_options:RxQueueOptions=RxQueueOptions();exhausting:bool=false) {
    rx_queue_validate(queue_options)
    return <- rx_node(tag,(source <- source,selector <- selector,max_active=max_active,exhausting=exhausting,limits=RxQueueOptions(capacity=queue_options.capacity,policy=queue_options.policy)),type<U>)
}
def rx_switch_map(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;var selector:lambda<(value:T):auto>) {
    return <- rx_flat_node(RxSwitchMapTag(),source,selector,default<typedecl(invoke(selector,default<T>))>)
}
def rx_exhaust_map(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;var selector:lambda<(value:T):auto>) {
    return <- rx_flat_node(RxExhaustTag(),source,selector,default<typedecl(invoke(selector,default<T>))>,1,RxQueueOptions(),true)
}

def rx_flat_map(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;var selector:lambda<(value:T):auto>) {
    return <- rx_flat_node(RxFlatMapTag(),source,selector,default<typedecl(invoke(selector,default<T>))>)
}
def rx_flat_map(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(FlatInput)>>;var selector:lambda<(value:FlatInput):auto>;max_active:int) {
    if(max_active<=0) {panic("rx_flat_map: max_active must be positive")}
    return <- rx_flat_node(RxFlatMapTag(),source,selector,default<typedecl(invoke(selector,default<FlatInput>))>,max_active)
}
def rx_concat_map(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(ConcatInput)>>;var selector:lambda<(value:ConcatInput):auto>) {
    return <- rx_flat_map(source,selector,1)
}
def rx_flat_map(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(FlatInput)>>;var selector:lambda<(value:FlatInput):auto>;max_active:int;queue_options:RxQueueOptions) {
    if(max_active<=0) {panic("rx_flat_map: max_active must be positive")}
    return <- rx_flat_node(RxFlatMapTag(),source,selector,default<typedecl(invoke(selector,default<FlatInput>))>,max_active,queue_options)
}
def rx_concat_map(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(ConcatInput)>>;var selector:lambda<(value:ConcatInput):auto>;queue_options:RxQueueOptions) {
    return <- rx_flat_map(source,selector,1,queue_options)
}

def private rx_flat_child(id:uint64;marker:type<auto(U)>) {
    return <- rx_node(RxFlatChildTag(),RxFlatChildState(control <- rx_subscription(),id=id),type<U>)
}

// Detach the owning list before invoking teardown. Callbacks retain their own
// child leases, so erasing/reallocating the list cannot invalidate active frames.
def private rx_flat_stop_children(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        var children <- state.data.children
        for(child in children) {rx_state(child).data.active=false}
        var failed=false
        var message=""
        for(child in children) {
            try {rx_unsubscribe(rx_state(child).data.control);rx_cleanup(rx_control(rx_state(child).data.control))} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        }
        delete children
        if(failed) {panic(message)}
    }
}
def private rx_flat_cancel(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        state.data.stopped=true
        delete state.data.queue
        delete state.data.pending
        var failed=false
        var message=""
        try {rx_unsubscribe(state.data.outer);rx_cleanup(rx_control(state.data.outer))} recover {failed=true;message="{this_context().last_exception}"}
        try {rx_flat_stop_children(run)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        if(failed) {panic(message)}
    }
}
def private rx_flat_error(run:auto;message:string) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        try {rx_flat_cancel(run)} recover {}
        var event:typedecl(state.data.queue[0]) -const -&
        event.kind=1;event.error=string(message)
        state.data.queue |> push(event)
    }
    rx_serial_drain(run)
}
def private rx_flat_check_end(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        if(state.data.outer_finished && empty(state.data.children) && empty(state.data.pending) && !state.data.pumping) {
            state.data.stopped=true
            var event:typedecl(state.data.queue[0]) -const -&
            event.kind=2
            state.data.queue |> push(event)
        }
    }
    rx_serial_drain(run)
}
def private rx_flat_child_finished(run,child:auto) : void {
    unsafe {
        let state=rx_state(run)
        let inner=rx_state(child)
        if(!inner.data.active || state.data.stopped || rx_stopped(state.data.observer)) {return}
        inner.data.active=false
        state.data.finishing++
        var failed=false
        var message=""
        try {rx_cleanup(rx_control(inner.data.control))} recover {failed=true;message="{this_context().last_exception}"}
        // Find again after cleanup: teardown may reenter and change the list.
        for(i in range(length(state.data.children))) {
            if(rx_state(state.data.children[i]).data.id==inner.data.id) {
                var removed <- state.data.children[i]
                state.data.children |> erase(i)
                delete removed
                break
            }
        }
        state.data.finishing--
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
    }
    rx_flat_pump(run)
    rx_flat_check_end(run)
}

// Only bounded flat_map uses this FIFO. Queue values, not projected sources:
// selector effects/resources start when a slot is actually available.
def private rx_flat_pump(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.max_active==0 || state.data.pumping || state.data.finishing!=0 || state.data.stopped || rx_stopped(state.data.observer)) {return}
        state.data.pumping=true
        var failed=false;var message=""
        try {
            while(!state.data.stopped && !rx_stopped(state.data.observer) && !empty(state.data.pending) && length(state.data.children)<state.data.max_active) {
                var value <- state.data.pending[0]
                state.data.pending |> erase(0)
                var projectFailed=false;var projectMessage=""
                try {rx_flat_project(run,value)} recover {projectFailed=true;projectMessage="{this_context().last_exception}"}
                try {rx_queue_dispose(value)} recover {if(!projectFailed) {projectFailed=true;projectMessage="{this_context().last_exception}"}}
                if(projectFailed) {panic(projectMessage)}
            }
        } recover {failed=true;message="{this_context().last_exception}"}
        state.data.pumping=false
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
    }
    rx_flat_check_end(run)
}
def private rx_flat_accept(run:auto;value:auto(QueuedInput)) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        if(state.data.exhausting && (state.data.pumping || state.data.finishing!=0 || !empty(state.data.children) || !empty(state.data.pending))) {return}
        if(state.data.max_active==0) {rx_flat_project(run,value);return}
        while(rx_queue_full(length(state.data.pending),state.data.limits)) {
            if(state.data.limits.policy==RxOverflowPolicy.error) {rx_flat_error(run,"rx_flat_map: queue overflow");return}
            if(state.data.limits.policy==RxOverflowPolicy.drop_latest) {return}
            rx_queue_drop_first(state.data.pending)
            if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        }
        static_if(typeinfo is_string(type<QueuedInput>)) {state.data.pending |> push(clone_string(value))}
        else {
            static_if(typeinfo can_copy(type<QueuedInput>)) {state.data.pending |> push(value)}
            else {state.data.pending |> emplace(rx_ref(value))}
        }
    }
    rx_flat_pump(run)
}
def private rx_flat_start_child(run,child:auto;source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(U)>>) : void {
    unsafe {
        let state=rx_state(run)
        let inner=rx_state(child)
        var values <- rx_ref(run);var valueChild <- rx_ref(child)
        var errors <- rx_ref(run);var errorChild <- rx_ref(child)
        var completed <- rx_ref(run);var doneChild <- rx_ref(child)
        var on_next <- @ capture(<-values,<-valueChild) (value:U) {
            unsafe {
                let target=rx_state(values)
                if(!rx_state(valueChild).data.active || target.data.stopped || rx_stopped(target.data.observer)) {return}
                target.data.queue |> push((kind=0,value=value,error=""))
            }
            rx_serial_drain(values)
        } finally {rx_finalize($ {delete valueChild;delete values})}
        var on_error <- @ capture(<-errors,<-errorChild) (message:string) {
            unsafe {if(rx_state(errorChild).data.active) {rx_flat_error(errors,message)}}
        } finally {rx_finalize($ {delete errorChild;delete errors})}
        var on_complete <- @ capture(<-completed,<-doneChild) () {
            unsafe {
                let target=rx_state(doneChild)
                target.data.done=true
                if(!target.data.connecting) {rx_flat_child_finished(completed,doneChild)}
            }
        } finally {rx_finalize($ {delete doneChild;delete completed})}
        rx_subscribe_with(inner.data.control,source,on_next,on_error,on_complete)
        inner.data.connecting=false
        if(inner.data.done) {rx_flat_child_finished(run,child)}
    }
}
def private rx_flat_project(run:tuple<tag:RxFlatRunTag;owner:iterator<auto?>;element:iterator<auto(U)>>;value:auto) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        state.data.serial++
        let id=state.data.serial
        if(state.data.switching) {
            clear(state.data.queue)
            var stopFailed=false
            var stopMessage=""
            try {rx_flat_stop_children(run)} recover {stopFailed=true;stopMessage="{this_context().last_exception}"}
            if(stopFailed) {
                try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
                panic(stopMessage)
            }
            if(state.data.stopped || rx_stopped(state.data.observer) || state.data.serial!=id) {return}
        }
        var mapped:typedecl(invoke(rx_state(state.data.source).data.selector,value)) -const -&
        var failed=false
        var message=""
        try {mapped <- invoke(rx_state(state.data.source).data.selector,value)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {delete mapped;rx_flat_error(run,message);return}
        if(state.data.stopped || rx_stopped(state.data.observer) || (state.data.switching && state.data.serial!=id)) {delete mapped;return}
        if(empty(mapped.owner)) {delete mapped;rx_flat_error(run,"rx: selector returned a moved or deleted Observable");return}
        var child <- rx_flat_child(id,type<U>)
        state.data.children |> emplace(rx_ref(child))
        try {rx_flat_start_child(run,child,mapped)} recover {failed=true;message="{this_context().last_exception}"}
        delete mapped
        delete child
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
    }
}
def private rx_flat_outer_finished(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        var failed=false
        var message=""
        try {rx_cleanup(rx_control(state.data.outer))} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
        state.data.outer_finished=true
    }
    rx_flat_check_end(run)
}
def private rx_flat_start_outer(run:auto;source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>) : void {
    unsafe {
        let state=rx_state(run)
        var values <- rx_ref(run)
        var errors <- rx_ref(run)
        var completed <- rx_ref(run)
        var on_next <- @ capture(<-values) (value:T) {rx_flat_accept(values,value)} finally {rx_finalize($ {delete values})}
        var on_error <- @ capture(<-errors) (message:string) {rx_flat_error(errors,message)} finally {rx_finalize($ {delete errors})}
        var on_complete <- @ capture(<-completed) () {
            unsafe {
                let target=rx_state(completed)
                target.data.outer_done=true
                if(!target.data.outer_connecting) {rx_flat_outer_finished(completed)}
            }
        } finally {rx_finalize($ {delete completed})}
        rx_subscribe_with(state.data.outer,source,on_next,on_error,on_complete)
        state.data.outer_connecting=false
        if(state.data.outer_done) {rx_flat_outer_finished(run)}
    }
}
def private rx_flat_connect_typed(source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(U)>>;observer:auto;switching:bool;input:iterator<auto(PendingInput)>) : void {
    var children:array<typedecl(rx_flat_child(uint64(0),type<U>)) -const -&>
    var queue:array<tuple<kind:int;value:U;error:string>>
    var pending:array<PendingInput>
    var run <- rx_node(RxFlatRunTag(),(source <- rx_ref(source),observer <- rx_ref(observer),outer <- rx_subscription(),
        children <- children,queue <- queue,pending <- pending,limits=RxQueueOptions(capacity=rx_state(source).data.limits.capacity,policy=rx_state(source).data.limits.policy),max_active=rx_state(source).data.max_active,exhausting=rx_state(source).data.exhausting,pumping=false,finishing=0,serial=uint64(0),switching=switching,stopped=false,dispatching=false,
        outer_connecting=true,outer_done=false,outer_finished=false),type<U>)
    var keeper <- rx_ref(run)
    var cleanup <- @ capture(<-keeper) () {rx_flat_cancel(keeper)} finally {rx_finalize($ {delete keeper})}
    unsafe {rx_add_cleanup(rx_state(observer).control,cleanup)}
    var failed=false
    var message=""
    unsafe {try {rx_flat_start_outer(run,rx_state(source).data.source)} recover {failed=true;message="{this_context().last_exception}"}}
    if(failed) {unsafe {try {rx_unsubscribe(rx_state(observer).control)} recover {}}}
    delete run
    if(failed) {panic(message)}
}
def private rx_flat_connect(source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;observer:auto;switching:bool) : void {
    unsafe {rx_flat_connect_typed(source,observer,switching,rx_state(source).data.source.element)}
}
def rx_connect(source:tuple<tag:RxSwitchMapTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {rx_flat_connect(source,observer,true)}
def rx_connect(source:tuple<tag:RxFlatMapTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {rx_flat_connect(source,observer,false)}

def rx_connect(source:tuple<tag:RxExhaustTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {rx_flat_connect(source,observer,false)}

struct RxTimerTag {_marker:uint8}
struct RxTimeTag {_marker:uint8}
struct RxTimeRunTag {_marker:uint8}
// mode: 0 timer, 1 interval, 2 delay, 3 debounce, 4 timeout, 5 observe_on.
def rx_timer(duration_ms:int|int64;scheduler:RxScheduler) {
    if(duration_ms<0) {panic("rx_timer: negative duration")}
    return <- rx_node(RxTimerTag(),(clock <- rx_scheduler_clone(scheduler),duration=int64(duration_ms),mode=0,limits=RxQueueOptions()),type<int64>)
}
def rx_interval(period_ms:int|int64;scheduler:RxScheduler) {
    if(period_ms<=0) {panic("rx_interval: period must be positive")}
    return <- rx_node(RxTimerTag(),(clock <- rx_scheduler_clone(scheduler),duration=int64(period_ms),mode=1,limits=RxQueueOptions()),type<int64>)
}
def private rx_time_node(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;duration_ms:int64;scheduler:RxScheduler;mode:int;queue_options:RxQueueOptions=RxQueueOptions()) {
    rx_queue_validate(queue_options)
    if(duration_ms<0) {panic("rx time operator: negative duration")}
    return <- rx_node(RxTimeTag(),(source <- source,clock <- rx_scheduler_clone(scheduler),duration=duration_ms,mode=mode,limits=RxQueueOptions(capacity=queue_options.capacity,policy=queue_options.policy)),type<T>)
}
def rx_delay(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;duration_ms:int|int64;scheduler:RxScheduler) {return <- rx_time_node(source,int64(duration_ms),scheduler,2)}
def rx_delay(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;duration_ms:int|int64;scheduler:RxScheduler;queue_options:RxQueueOptions) {return <- rx_time_node(source,int64(duration_ms),scheduler,2,queue_options)}

def rx_observe_on(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;scheduler:RxScheduler;queue_options:RxQueueOptions=rx_queue(256)) {
    if(queue_options.capacity<=0) {panic("rx_observe_on: capacity must be positive")}
    return <- rx_time_node(source,0l,scheduler,5,queue_options)
}

// Reuse the timer's cancellation/clock lifecycle and flat_map's child ownership.
// Only connection is scheduled; disposal remains immediate on this event loop.
def rx_subscribe_on(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;scheduler:RxScheduler) {
    return <- rx_timer(0,scheduler) |> rx_flat_map(@ capture(<-source) (unused:int64) {return <- rx_clone(source)} finally {delete source})
}

def rx_debounce(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;duration_ms:int|int64;scheduler:RxScheduler) {return <- rx_time_node(source,int64(duration_ms),scheduler,3)}
def rx_timeout(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;duration_ms:int|int64;scheduler:RxScheduler) {return <- rx_time_node(source,int64(duration_ms),scheduler,4)}

def private rx_time_clear(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        var pending <- state.data.pending
        for(item in pending) {rx_cancel(state.data.clock,item.handle)}
        delete pending
    }
}
def private rx_time_cancel(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        state.data.stopped=true
        delete state.data.queue;delete state.data.latest
        rx_cancel(state.data.clock,state.data.lifecycle)
        rx_time_clear(run)
        rx_unsubscribe(state.data.child);rx_cleanup(rx_control(state.data.child))
    }
}
def private rx_time_error(run:auto;message:string) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        try {rx_time_cancel(run)} recover {}
        var event:typedecl(state.data.queue[0]) -const -&
        event.kind=1;event.error=string(message)
        state.data.queue |> push(event)
    }
    rx_serial_drain(run)
}
def private rx_time_done(run:auto;flush:bool=false) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        if(flush && !empty(state.data.latest)) {state.data.queue |> push((kind=0,value=state.data.latest[0],error=""))}
        var pending <- state.data.queue
        var failed=false
        var message=""
        try {rx_time_cancel(run)} recover {failed=true;message="{this_context().last_exception}"}
        state.data.queue <- pending
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
        var event:typedecl(state.data.queue[0]) -const -&
        event.kind=2
        state.data.queue |> push(event)
    }
    rx_serial_drain(run)
}
def private rx_time_remove(run:auto;serial:uint64) : void {
    unsafe {
        let state=rx_state(run)
        for(i in range(length(state.data.pending))) {
            if(state.data.pending[i].serial==serial) {state.data.pending |> erase(i);break}
        }
    }
}
def private rx_time_fire(run:auto;serial:uint64;kind:int;value:auto;error_message:string) : void {
    rx_time_remove(run,serial)
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        if(kind==2) {rx_time_error(run,"rx timeout");return}
        if(kind==3) {rx_time_error(run,error_message);return}
        if(kind==1) {rx_time_done(run);return}
        clear(state.data.latest)
        state.data.queue |> push((kind=0,value=value,error=""))
    }
    rx_serial_drain(run)
}
def private rx_time_schedule(run:auto;duration:int64;kind:int;value:auto;error_message:string="") : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        if((state.data.mode==2 || state.data.mode==5) && kind==0 && state.data.limits.capacity>0) {
            // A cancelled payload finalizer can reenter the producer.
            while(!state.data.stopped && !rx_stopped(state.data.observer)) {
                var count=0;var oldest=-1
                for(i in range(length(state.data.pending))) {
                    if(state.data.pending[i].kind==0) {count++;if(oldest<0) {oldest=i}}
                }
                if(!rx_queue_full(count,state.data.limits)) {break}
                if(state.data.limits.policy==RxOverflowPolicy.error) {
                    if(state.data.mode==5) {
                        // Overflow discards the queue, but its notification is
                        // still delivered on the scheduler, never in producer code.
                        state.data.done=true
                        state.data.input_finished=true
                        state.data.input_error="rx_observe_on: queue overflow"
                        rx_time_clear(run)
                        rx_unsubscribe(state.data.child);rx_cleanup(rx_control(state.data.child))
                        var unused:typedecl(value) -const -&
                        rx_time_schedule(run,0l,3,unused,state.data.input_error)
                    } else {rx_time_error(run,"rx_delay: queue overflow")}
                    return
                }
                if(state.data.limits.policy==RxOverflowPolicy.drop_latest) {return}
                var discarded=state.data.pending[oldest].handle
                state.data.pending |> erase(oldest)
                rx_cancel(state.data.clock,discarded)
                if(state.data.stopped || rx_stopped(state.data.observer)) {return}
                if(state.data.mode==5 && state.data.done) {return}
            }
        }
        state.data.serial++
        let serial=state.data.serial
        var owner <- rx_ref(run)
        var closing <- rx_ref(run)
        var saved:typedecl(value) -const -&
        var saved_error=clone_string(error_message)
        static_if(typeinfo is_string(type<typedecl(value) -const -&>)) {saved=clone_string(value)}
        else {saved=value}
        var action <- @ capture(<-owner,copy(serial),copy(kind),<-saved,<-saved_error) () {rx_time_fire(owner,serial,kind,saved,saved_error)} finally {rx_finalize($ {
            var failed=false;var message=""
            try {rx_queue_dispose(saved)} recover {failed=true;message="{this_context().last_exception}"}
            delete owner
            if(failed) {panic(message)}
        })}
        var on_close <- @ capture(<-closing) () {rx_time_error(closing,"rx scheduler closed")} finally {rx_finalize($ {delete closing})}
        var handle:RxScheduledId
        var failed=false
        var message=""
        try {handle=rx_schedule(state.data.clock,duration,action,on_close)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {rx_time_error(run,message);return}
        state.data.pending |> push((serial=serial,handle=handle,kind=kind))
    }
}
def private rx_timer_schedule(run:auto;duration:int64) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        state.data.serial++
        let serial=state.data.serial
        var owner <- rx_ref(run)
        var closing <- rx_ref(run)
        var action <- @ capture(<-owner,copy(serial)) () {
            rx_time_remove(owner,serial)
            unsafe {
                let target=rx_state(owner)
                if(target.data.stopped || rx_stopped(target.data.observer)) {return}
                target.data.queue |> push((kind=0,value=target.data.counter,error=""))
                target.data.counter++
                if(target.data.mode==0) {rx_time_done(owner)}
                else {
                    rx_serial_drain(owner)
                    if(!target.data.stopped && !rx_stopped(target.data.observer)) {rx_timer_schedule(owner,target.data.duration)}
                }
            }
        } finally {rx_finalize($ {delete owner})}
        var on_close <- @ capture(<-closing) () {rx_time_error(closing,"rx scheduler closed")} finally {rx_finalize($ {delete closing})}
        var handle:RxScheduledId
        var failed=false
        var message=""
        try {handle=rx_schedule(state.data.clock,duration,action,on_close)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {rx_time_error(run,message);return}
        state.data.pending |> push((serial=serial,handle=handle,kind=0))
    }
}
def private rx_time_run(source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;observer:auto) {
    unsafe {
        let input=rx_state(source)
        var queue:array<tuple<kind:int;value:T;error:string>>
        var latest:array<T>
        var pending:array<tuple<serial:uint64;handle:RxScheduledId;kind:int>>
        return <- rx_node(RxTimeRunTag(),(source <- rx_ref(source),observer <- rx_ref(observer),clock <- rx_scheduler_clone(input.data.clock),
            child <- rx_subscription(),queue <- queue,latest <- latest,pending <- pending,serial=uint64(0),lifecycle=RxScheduledId(),
            limits=RxQueueOptions(capacity=input.data.limits.capacity,policy=input.data.limits.policy),mode=input.data.mode,duration=input.data.duration,counter=0l,stopped=false,dispatching=false,connecting=true,done=false,input_error="",input_failed=false,input_finished=false),type<T>)
    }
}
def private rx_time_cleanup(run:auto;observer:auto) {
    var owner <- rx_ref(run)
    var action <- @ capture(<-owner) () {rx_time_cancel(owner)} finally {rx_finalize($ {delete owner})}
    unsafe {rx_add_cleanup(rx_state(observer).control,action)}
    var closing <- rx_ref(run)
    var on_close <- @ capture(<-closing) () {rx_time_error(closing,"rx scheduler closed")} finally {rx_finalize($ {delete closing})}
    unsafe {rx_state(run).data.lifecycle=rx_on_scheduler_close(rx_state(run).data.clock,on_close)}
}
def rx_connect(source:tuple<tag:RxTimerTag;owner:iterator<auto?>;element:iterator<int64>>;observer:auto) : void {
    var run <- rx_time_run(source,observer)
    var failed=false
    var message=""
    unsafe {
        try {rx_time_cleanup(run,observer);rx_timer_schedule(run,rx_state(source).data.duration)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {try {rx_unsubscribe(rx_state(observer).control)} recover {}}
    }
    delete run
    if(failed) {panic(message)}
}
def private rx_time_input_finished(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        if(state.data.mode==5 && state.data.input_finished) {return}
        state.data.input_finished=true
        var failed=false
        var message=""
        try {rx_cleanup(rx_control(state.data.child))} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {};panic(message)}
        if(state.data.mode==2 || state.data.mode==5) {
            var value:typedecl(state.data.latest[0]) -const -&
            rx_time_schedule(run,state.data.duration,state.data.input_failed ? 3 : 1,value,state.data.input_error)
        } else {rx_time_done(run,state.data.mode==3)}
    }
}
def private rx_time_start(run:auto;source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>) : void {
    unsafe {
        let state=rx_state(run)
        var values <- rx_ref(run)
        var errors <- rx_ref(run)
        var completed <- rx_ref(run)
        var on_next <- @ capture(<-values) (value:T) {
            unsafe {
                let target=rx_state(values)
                if(target.data.stopped || rx_stopped(target.data.observer)) {return}
                if(target.data.mode==5 && target.data.done) {return}
                if(target.data.mode==3) {
                    rx_time_clear(values);clear(target.data.latest);target.data.latest |> push(value)
                    rx_time_schedule(values,target.data.duration,0,value)
                } elif(target.data.mode==4) {
                    rx_time_clear(values)
                    rx_time_schedule(values,target.data.duration,2,value)
                    if(!target.data.stopped) {target.data.queue |> push((kind=0,value=value,error=""));rx_serial_drain(values)}
                } else {rx_time_schedule(values,target.data.duration,0,value)}
            }
        } finally {rx_finalize($ {delete values})}
        var on_error <- @ capture(<-errors) (message:string) {
            unsafe {
                let target=rx_state(errors)
                if(target.data.mode==5) {
                    if(target.data.done || target.data.stopped) {return}
                    target.data.done=true;target.data.input_failed=true;target.data.input_error=clone_string(message)
                    if(!target.data.connecting) {rx_time_input_finished(errors)}
                } else {rx_time_error(errors,message)}
            }
        } finally {rx_finalize($ {delete errors})}
        var on_complete <- @ capture(<-completed) () {
            unsafe {let target=rx_state(completed);target.data.done=true;if(!target.data.connecting) {rx_time_input_finished(completed)}}
        } finally {rx_finalize($ {delete completed})}
        rx_subscribe_with(state.data.child,source,on_next,on_error,on_complete)
        state.data.connecting=false
        if(state.data.done) {rx_time_input_finished(run)}
    }
}
def rx_connect(source:tuple<tag:RxTimeTag;owner:iterator<auto?>;element:iterator<auto(T)>>;observer:auto) : void {
    var run <- rx_time_run(source,observer)
    var failed=false
    var message=""
    unsafe {
        try {
            rx_time_cleanup(run,observer)
            let state=rx_state(run)
            if(state.data.mode==4) {rx_time_schedule(run,state.data.duration,2,default<T>)}
            if(!state.data.stopped) {rx_time_start(run,rx_state(source).data.source)}
        } recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {try {rx_unsubscribe(rx_state(observer).control)} recover {}}
    }
    delete run
    if(failed) {panic(message)}
}

// Extension seam: factories receive a borrowed sink. Retain it explicitly for
// callbacks and register teardown before starting an external operation.
struct RxCreateTag {_marker:uint8}
def rx_create(unused:type<auto(RxCreatedItem)>;var factory:auto) {return <- rx_node(RxCreateTag(),(factory <- factory),type<RxCreatedItem>)}
def rx_sink_marker(unused:type<auto(RxSinkItem)>) {return <- rx_observer_marker(type<RxSinkItem>)}
def rx_sink_clone(sink:auto) {return <- rx_ref(sink)}
def rx_sink_next(sink:auto;value:auto) {rx_next(sink,value)}
def rx_sink_error(sink:auto;message:string) {rx_error(sink,message)}
def rx_sink_complete(sink:auto) {rx_done(sink)}
def rx_sink_stopped(sink:auto) : bool {return rx_stopped(sink)}
def rx_sink_add_cleanup(sink:auto;var action:lambda<():void>) {unsafe {rx_add_cleanup(rx_state(sink).control,action)}}
def rx_connect(source:tuple<tag:RxCreateTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {unsafe {invoke(rx_state(source).data.factory,observer)}}

struct RxJustTag {_marker:uint8}
struct RxEmptyTag {_marker:uint8}
struct RxThrowTag {_marker:uint8}
def rx_just(value:auto(RxJustItem)) {
    static_if(typeinfo is_string(type<RxJustItem>)) {return <- rx_node(RxJustTag(),(value=string(value)),type<string>)}
    else {return <- rx_node(RxJustTag(),(value=value),type<RxJustItem>)}
}
def rx_empty(unused:type<auto(RxEmptyItem)>) {return <- rx_node(RxEmptyTag(),(empty=true),type<RxEmptyItem>)}
def rx_throw(message:string;unused:type<auto(RxErrorItem)>) {return <- rx_node(RxThrowTag(),(message=string(message)),type<RxErrorItem>)}
def rx_connect(source:tuple<tag:RxJustTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {
    unsafe {rx_next(observer,rx_state(source).data.value)}
    rx_done(observer)
}
def rx_connect(source:tuple<tag:RxEmptyTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {rx_done(observer)}
def rx_connect(source:tuple<tag:RxThrowTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {unsafe {rx_error(observer,rx_state(source).data.message)}}

struct RxCatchTag {_marker:uint8}
struct RxRetryTag {_marker:uint8}
struct RxRecoveryRunTag {_marker:uint8}
struct RxCatchPolicy {_marker:uint8}
struct RxRetryPolicy {_marker:uint8}
def private rx_catch_node(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(RxCaughtItem)>>;var handler:auto;
    marker:tuple<tag:auto;owner:iterator<auto?>;element:iterator<RxCaughtItem>>) {
    return <- rx_node(RxCatchTag(),(source <- source,handler <- handler),type<RxCaughtItem>)
}
def rx_catch_error(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;var handler:lambda<(message:string):auto>) {
    return <- rx_catch_node(source,handler,default<typedecl(invoke(handler,""))>)
}
// retries counts additional subscriptions; even delay=0 is scheduled, avoiding
// recursive resubscription and allowing cancellation between synchronous failures.
def rx_retry(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;retries:int;var predicate:lambda<(message:string;retry:int):bool>;var delay_for:lambda<(retry:int):int64>;scheduler:RxScheduler) {
    if(retries<0) {delete source;unsafe {delete predicate;delete delay_for};panic("rx_retry: retries must be nonnegative")}
    return <- rx_node(RxRetryTag(),(source <- source,retries=retries,predicate <- predicate,delay_for <- delay_for,clock <- rx_scheduler_clone(scheduler)),type<T>)
}

def rx_retry(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;retries:int;delay_ms:int|int64;scheduler:RxScheduler) {
    if(retries<0 || delay_ms<0) {delete source;panic("rx_retry: retries and delay must be nonnegative")}
    let duration=int64(delay_ms)
    return <- rx_retry(source,retries,@(message:string;retry:int) {return true},@ capture(copy(duration)) (retry:int) {return duration},scheduler)
}

def rx_retry_backoff(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;retries:int;initial_ms:int|int64;max_ms:int|int64;scheduler:RxScheduler;var predicate:lambda<(message:string;retry:int):bool>) {
    if(initial_ms<0 || max_ms<initial_ms) {delete source;unsafe {delete predicate};panic("rx_retry_backoff: require 0 <= initial <= max")}
    let initial=int64(initial_ms);let cap=int64(max_ms)
    return <- rx_retry(source,retries,predicate,@ capture(copy(initial),copy(cap)) (retry:int) {
        var delay=initial;var index=1
        while(index<retry && delay>0l && delay<cap) {delay=delay>cap/2l ? cap : delay*2l;index++}
        return delay
    },scheduler)
}

def rx_retry_backoff(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;retries:int;initial_ms:int|int64;max_ms:int|int64;scheduler:RxScheduler) {
    return <- rx_retry_backoff(source,retries,initial_ms,max_ms,scheduler,@(message:string;retry:int) {return true})
}

def private rx_recovery_unschedule(run:auto;policy:RxCatchPolicy) : void {}
def private rx_recovery_unschedule(run:auto;policy:RxRetryPolicy) : void {
    unsafe {
        let state=rx_state(run)
        rx_cancel(state.data.clock,state.data.scheduled)
        rx_cancel(state.data.clock,state.data.lifecycle)
    }
}
def private rx_recovery_cancel(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        state.data.stopped=true
        delete state.data.queue
        rx_recovery_unschedule(run,state.data.policy)
        rx_unsubscribe(state.data.child);rx_cleanup(rx_control(state.data.child))
    }
}
def private rx_recovery_terminal(run:auto;failed:bool;message:string="") : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        var pending:typedecl(state.data.queue) -const -&
        if(!failed) {pending <- state.data.queue}
        var cleanupFailed=false
        var cleanupMessage=""
        try {rx_recovery_cancel(run)} recover {cleanupFailed=true;cleanupMessage="{this_context().last_exception}"}
        state.data.queue <- pending
        if(cleanupFailed && !failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(cleanupMessage)
        }
        var event:typedecl(state.data.queue[0]) -const -&
        event.kind=failed ? 1 : 2;event.error=string(message)
        state.data.queue |> push(event)
    }
    rx_serial_drain(run)
}
def private rx_recovery_advance(run:auto;policy:RxCatchPolicy) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.fallback) {rx_recovery_terminal(run,true,state.data.error);return}
        state.data.fallback=true
        var replacement:typedecl(invoke(rx_state(state.data.source).data.handler,state.data.error)) -const -&
        var failed=false
        var message=""
        try {replacement <- invoke(rx_state(state.data.source).data.handler,state.data.error)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {delete replacement;rx_recovery_terminal(run,true,message);return}
        if(state.data.stopped || rx_stopped(state.data.observer)) {delete replacement;return}
        if(empty(replacement.owner)) {delete replacement;rx_recovery_terminal(run,true,"rx_catch_error: handler returned a moved or deleted Observable");return}
        try {rx_recovery_start(run,replacement)} recover {failed=true;message="{this_context().last_exception}"}
        delete replacement
        if(failed) {panic(message)}
    }
}
def private rx_recovery_advance(run:auto;policy:RxRetryPolicy) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.remaining==0) {rx_recovery_terminal(run,true,state.data.error);return}
        var delay=0l;var accepted=false;var policyFailed=false;var policyError=""
        try {
            accepted=invoke(rx_state(state.data.source).data.predicate,state.data.error,int(state.data.attempt))
            if(accepted) {delay=invoke(rx_state(state.data.source).data.delay_for,int(state.data.attempt));if(delay<0) {panic("rx_retry: negative delay")}}
        } recover {policyFailed=true;policyError="{this_context().last_exception}"}
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        if(policyFailed) {rx_recovery_terminal(run,true,policyError);return}
        if(!accepted) {rx_recovery_terminal(run,true,state.data.error);return}
        state.data.remaining--
        var owner <- rx_ref(run)
        var action <- @ capture(<-owner) () {
            unsafe {
                let target=rx_state(owner)
                target.data.scheduled=RxScheduledId()
                if(!target.data.stopped && !rx_stopped(target.data.observer)) {rx_recovery_start(owner,rx_state(target.data.source).data.source)}
            }
        } finally {rx_finalize($ {delete owner})}
        var failed=false
        var message=""
        try {state.data.scheduled=rx_schedule(state.data.clock,delay,action)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {rx_recovery_terminal(run,true,message)}
    }
}
def private rx_recovery_pump(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.pumping || state.data.connecting) {return}
        state.data.pumping=true
        var failed=false
        var message=""
        try {
            while(state.data.ended && !state.data.stopped && !rx_stopped(state.data.observer)) {
                state.data.ended=false
                // Drain late teardown before calling a fallback factory or
                // scheduling retry. The previous root may still be on stack.
                rx_cleanup(rx_control(state.data.child))
                if(state.data.stopped || rx_stopped(state.data.observer)) {break}
                if(state.data.failed) {rx_recovery_advance(run,state.data.policy)}
                else {rx_recovery_terminal(run,false)}
            }
        } recover {failed=true;message="{this_context().last_exception}"}
        state.data.pumping=false
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
    }
}
def private rx_recovery_start(run:auto;source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(RxRecoveryItem)>>) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        rx_unsubscribe(state.data.child);rx_cleanup(rx_control(state.data.child));delete state.data.child
        state.data.child <- rx_subscription()
        state.data.connecting=true;state.data.ended=false
        state.data.attempt++
        let attempt=state.data.attempt
        var values <- rx_ref(run)
        var errors <- rx_ref(run)
        var completed <- rx_ref(run)
        var on_next <- @ capture(<-values,copy(attempt)) (value:RxRecoveryItem) {
            unsafe {
                let target=rx_state(values)
                if(target.data.stopped || target.data.attempt!=attempt || rx_stopped(target.data.observer)) {return}
                target.data.queue |> push((kind=0,value=value,error=""))
            }
            rx_serial_drain(values)
        } finally {rx_finalize($ {delete values})}
        var on_error <- @ capture(<-errors,copy(attempt)) (message:string) {
            unsafe {
                let target=rx_state(errors)
                if(target.data.stopped || target.data.attempt!=attempt) {return}
                target.data.ended=true;target.data.failed=true;target.data.error=string(message)
            }
            rx_recovery_pump(errors)
        } finally {rx_finalize($ {delete errors})}
        var on_complete <- @ capture(<-completed,copy(attempt)) () {
            unsafe {
                let target=rx_state(completed)
                if(target.data.stopped || target.data.attempt!=attempt) {return}
                target.data.ended=true;target.data.failed=false
            }
            rx_recovery_pump(completed)
        } finally {rx_finalize($ {delete completed})}
        var failed=false
        var message=""
        try {rx_subscribe_with(state.data.child,source,on_next,on_error,on_complete)} recover {failed=true;message="{this_context().last_exception}"}
        state.data.connecting=false
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
    }
    rx_recovery_pump(run)
}
def private rx_recovery_run(source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(RxRecoveryValue)>>;observer:auto;policy:auto;remaining:int;var clock:RxScheduler) {
    var queue:array<tuple<kind:int;value:RxRecoveryValue;error:string>>
    return <- rx_node(RxRecoveryRunTag(),(source <- rx_ref(source),observer <- rx_ref(observer),child <- rx_subscription(),clock <- clock,
        queue <- queue,policy=policy,remaining=remaining,scheduled=RxScheduledId(),lifecycle=RxScheduledId(),
        stopped=false,dispatching=false,pumping=false,connecting=false,ended=false,failed=false,fallback=false,error="",attempt=uint64(0)),type<RxRecoveryValue>)
}
def private rx_recovery_cleanup(run:auto;observer:auto) : void {
    var owner <- rx_ref(run)
    var cleanup <- @ capture(<-owner) () {rx_recovery_cancel(owner)} finally {rx_finalize($ {delete owner})}
    unsafe {rx_add_cleanup(rx_state(observer).control,cleanup)}
}
def rx_connect(source:tuple<tag:RxCatchTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {
    var clock:RxScheduler
    var run <- rx_recovery_run(source,observer,RxCatchPolicy(),0,clock)
    var failed=false
    var message=""
    try {
        rx_recovery_cleanup(run,observer)
        unsafe {rx_recovery_start(run,rx_state(source).data.source)}
    } recover {failed=true;message="{this_context().last_exception}"}
    delete run
    if(failed) {panic(message)}
}
def rx_connect(source:tuple<tag:RxRetryTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {
    var clock <- rx_scheduler_clone(unsafe(rx_state(source).data.clock))
    var run <- rx_recovery_run(source,observer,RxRetryPolicy(),unsafe(rx_state(source).data.retries),clock)
    var failed=false
    var message=""
    try {
        rx_recovery_cleanup(run,observer)
        var closing <- rx_ref(run)
        var on_close <- @ capture(<-closing) () {rx_recovery_terminal(closing,true,"rx scheduler closed")} finally {rx_finalize($ {delete closing})}
        unsafe {
            let state=rx_state(run)
            state.data.lifecycle=rx_on_scheduler_close(state.data.clock,on_close)
            if(!state.data.stopped && !rx_stopped(observer)) {rx_recovery_start(run,rx_state(source).data.source)}
        }
    } recover {failed=true;message="{this_context().last_exception}"}
    if(failed) {unsafe {try {rx_unsubscribe(rx_state(observer).control)} recover {}}}
    delete run
    if(failed) {panic(message)}
}


// Rate control and non-overlapping buffers. Each subscription owns its clocks,
// retained values, and serialized delivery frames independently.
struct RxThrottleTag {_marker:uint8}
struct RxSampleTag {_marker:uint8}
struct RxBufferTag {_marker:uint8}
struct RxGroupRunTag {_marker:uint8}
def private rx_group_periodic(policy:RxThrottleTag) : bool {return false}
def private rx_group_periodic(policy:RxSampleTag|RxBufferTag) : bool {return true}

def rx_throttle(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(RateItem)>>;duration_ms:int|int64;scheduler:RxScheduler) {
    if(duration_ms<=0) {panic("rx_throttle: duration must be positive")}
    return <- rx_node(RxThrottleTag(),(source <- source,clock <- rx_scheduler_clone(scheduler),duration=int64(duration_ms),count=0),type<RateItem>)
}
def rx_sample(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(RateItem)>>;period_ms:int|int64;scheduler:RxScheduler) {
    if(period_ms<=0) {panic("rx_sample: period must be positive")}
    return <- rx_node(RxSampleTag(),(source <- source,clock <- rx_scheduler_clone(scheduler),duration=int64(period_ms),count=0),type<RateItem>)
}
def private rx_buffer_node(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(BufferItem)>>;count:int;duration:int64;var clock:RxScheduler) {
    rx_check_payload(type<BufferItem>)
    return <- rx_storage_node(RxBufferTag(),(source <- source,clock <- clock,duration=duration,count=count),type<array<BufferItem>>)
}
def rx_buffer(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;count:int) {
    if(count<=0) {panic("rx_buffer: count must be positive")}
    var clock:RxScheduler
    return <- rx_buffer_node(source,count,0l,clock)
}
def rx_buffer_time(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;duration_ms:int|int64;scheduler:RxScheduler) {
    if(duration_ms<=0) {panic("rx_buffer_time: duration must be positive")}
    var clock <- rx_scheduler_clone(scheduler)
    return <- rx_buffer_node(source,0,int64(duration_ms),clock)
}
def rx_buffer(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;duration_ms:int|int64;scheduler:RxScheduler) {
    return <- rx_buffer_time(source,duration_ms,scheduler)
}
def rx_buffer(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;count:int;duration_ms:int|int64;scheduler:RxScheduler) {
    if(count<=0 || duration_ms<=0) {panic("rx_buffer: count and duration must be positive")}
    var clock <- rx_scheduler_clone(scheduler)
    return <- rx_buffer_node(source,count,int64(duration_ms),clock)
}

def private rx_group_cancel(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        state.data.stopped=true
        var queue <- state.data.queue;var buffer <- state.data.buffer
        var failed=false;var message=""
        if(state.data.duration>0) {
            var timer=state.data.timer;state.data.timer=RxScheduledId()
            var lifecycle=state.data.lifecycle;state.data.lifecycle=RxScheduledId()
            try {rx_cancel(state.data.clock,timer)} recover {failed=true;message="{this_context().last_exception}"}
            try {rx_cancel(state.data.clock,lifecycle)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        }
        try {rx_unsubscribe(state.data.child);rx_cleanup(rx_control(state.data.child))} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        try {delete buffer} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        try {delete queue} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        if(failed) {panic(message)}
    }
}
def private rx_group_enqueue(run:auto;policy:RxBufferTag) : void {
    unsafe {
        let state=rx_state(run)
        if(empty(state.data.buffer)) {return}
        var batch <- state.data.buffer
        state.data.queue |> emplace((kind=0,value <- batch,error=""))
    }
}
def private rx_group_enqueue(run:auto;policy:RxSampleTag) : void {
    unsafe {
        let state=rx_state(run)
        if(empty(state.data.buffer)) {return}
        var value <- state.data.buffer[0];state.data.buffer |> erase(0)
        state.data.queue |> emplace((kind=0,value <- value,error=""))
    }
}
def private rx_group_enqueue(run:auto;policy:RxThrottleTag) : void {}

def private rx_group_terminal(run:auto;failed:bool;message:string="") : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        state.data.ending=true
        if(!failed) {rx_group_enqueue(run,state.data.policy)}
        var pending:typedecl(state.data.queue) -const -&
        if(!failed) {pending <- state.data.queue}
        var cleanupFailed=false;var cleanupMessage=""
        try {rx_group_cancel(run)} recover {cleanupFailed=true;cleanupMessage="{this_context().last_exception}"}
        state.data.queue <- pending
        if(cleanupFailed && !failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(cleanupMessage)
        }
        var event:typedecl(state.data.queue[0]) -const -&
        event.kind=failed ? 1 : 2;event.error=clone_string(message)
        state.data.queue |> emplace(event)
    }
    rx_serial_drain(run)
}

def private rx_group_arm(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        var previous=state.data.timer;state.data.timer=RxScheduledId()
        state.data.serial++
        let serial=state.data.serial
        rx_cancel(state.data.clock,previous)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        var owner <- rx_ref(run);var closing <- rx_ref(run)
        var action <- @ capture(<-owner,copy(serial)) () {
            unsafe {
                let target=rx_state(owner)
                if(target.data.stopped || rx_stopped(target.data.observer) || target.data.serial!=serial) {return}
                target.data.timer=RxScheduledId()
                rx_group_enqueue(owner,target.data.policy)
                rx_group_arm(owner)
            }
            rx_serial_drain(owner)
        } finally {rx_finalize($ {delete owner})}
        var on_close <- @ capture(<-closing) () {rx_group_terminal(closing,true,"rx scheduler closed")} finally {rx_finalize($ {delete closing})}
        var handle:RxScheduledId
        var failed=false;var message=""
        try {handle=rx_schedule(state.data.clock,state.data.duration,action,on_close)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {rx_group_terminal(run,true,message);return}
        state.data.timer=handle
    }
}
def private rx_group_push(var items:array<auto(GroupItem)>;value:GroupItem) {
    static_if(typeinfo is_string(type<GroupItem>)) {items |> push(clone_string(value))}
    else {items |> push(value)}
}
def private rx_group_accept(run:auto;value:auto;policy:RxThrottleTag) : void {
    unsafe {
        let state=rx_state(run)
        let now=rx_now_ms(state.data.clock)
        if(state.data.gated && now<state.data.until_ms) {return}
        if(now>9223372036854775807l-state.data.duration) {rx_group_terminal(run,true,"rx_throttle: deadline overflow");return}
        state.data.gated=true;state.data.until_ms=now+state.data.duration
        var saved:typedecl(value) -const -&
        static_if(typeinfo is_string(type<typedecl(value) -const -&>)) {saved=clone_string(value)} else {saved=value}
        state.data.queue |> emplace((kind=0,value <- saved,error=""))
    }
    rx_serial_drain(run)
}
def private rx_group_accept(run:auto;value:auto;policy:RxSampleTag) : void {
    unsafe {
        let state=rx_state(run)
        var previous <- state.data.buffer
        rx_group_push(state.data.buffer,value)
        delete previous
    }
}
def private rx_group_accept(run:auto;value:auto;policy:RxBufferTag) : void {
    unsafe {
        let state=rx_state(run)
        rx_group_push(state.data.buffer,value)
        if(state.data.count>0 && length(state.data.buffer)>=state.data.count) {
            rx_group_enqueue(run,policy)
            if(state.data.duration>0) {rx_group_arm(run)}
            rx_serial_drain(run)
        }
    }
}
def private rx_group_finished(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        var failed=false;var message=""
        try {rx_cleanup(rx_control(state.data.child))} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
    }
    rx_group_terminal(run,false)
}
def private rx_group_start(run:auto;source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(GroupInput)>>) : void {
    var values <- rx_ref(run);var errors <- rx_ref(run);var completed <- rx_ref(run)
    var on_next <- @ capture(<-values) (value:GroupInput) {
        unsafe {
            let state=rx_state(values)
            if(!state.data.stopped && !state.data.ending && !rx_stopped(state.data.observer)) {rx_group_accept(values,value,state.data.policy)}
        }
    } finally {rx_finalize($ {delete values})}
    var on_error <- @ capture(<-errors) (message:string) {rx_group_terminal(errors,true,message)} finally {rx_finalize($ {delete errors})}
    var on_complete <- @ capture(<-completed) () {
        unsafe {let state=rx_state(completed);state.data.done=true;if(!state.data.connecting) {rx_group_finished(completed)}}
    } finally {rx_finalize($ {delete completed})}
    unsafe {
        let state=rx_state(run)
        rx_subscribe_with(state.data.child,source,on_next,on_error,on_complete)
        state.data.connecting=false
        if(state.data.done) {rx_group_finished(run)}
    }
}
def private rx_group_connect_typed(source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(GroupOutput)>>;observer:auto;input:iterator<auto(GroupInput)>) : void {
    unsafe {
        let settings=rx_state(source)
        var buffer:array<GroupInput>
        var queue:array<tuple<kind:int;value:GroupOutput;error:string>>
        var clock:RxScheduler
        if(settings.data.duration>0) {clock <- rx_scheduler_clone(settings.data.clock)}
        var run <- rx_storage_node(RxGroupRunTag(),(source <- rx_ref(source),observer <- rx_ref(observer),child <- rx_subscription(),clock <- clock,
            buffer <- buffer,queue <- queue,policy=source.tag,duration=settings.data.duration,count=settings.data.count,
            timer=RxScheduledId(),lifecycle=RxScheduledId(),serial=uint64(0),gated=false,until_ms=0l,
            stopped=false,ending=false,dispatching=false,connecting=true,done=false),type<GroupOutput>)
        var keeper <- rx_ref(run)
        var cleanup <- @ capture(<-keeper) () {rx_group_cancel(keeper)} finally {rx_finalize($ {delete keeper})}
        var failed=false;var message=""
        try {
            rx_add_cleanup(rx_state(observer).control,cleanup)
            let state=rx_state(run)
            if(state.data.duration>0) {
                var closing <- rx_ref(run)
                var on_close <- @ capture(<-closing) () {rx_group_terminal(closing,true,"rx scheduler closed")} finally {rx_finalize($ {delete closing})}
                state.data.lifecycle=rx_on_scheduler_close(state.data.clock,on_close)
                if(rx_group_periodic(source.tag)) {rx_group_arm(run)}
            }
            if(!state.data.stopped && !rx_stopped(observer)) {rx_group_start(run,settings.data.source)}
        } recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {try {rx_unsubscribe(rx_state(observer).control)} recover {}}
        delete run
        if(failed) {panic(message)}
    }
}
def rx_connect(source:tuple<tag:RxThrottleTag|RxSampleTag|RxBufferTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {
    unsafe {rx_group_connect_typed(source,observer,rx_state(source).data.source.element)}
}

// Connectable sources keep the subject alive across manual disconnects. Only
// returned connection owners (or ref_count) own the upstream cancellation lease.
struct RxPublishTag {_marker:uint8}
struct RxRefCountTag {_marker:uint8}

def rx_publish(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>) {
    return <- rx_node(RxPublishTag(),(source <- source,subject <- rx_subject(type<T>),connection <- default<RxSubscription>,ref_connection <- default<RxSubscription>,listeners=0),type<T>)
}

def private rx_publish_abort(hub:auto;connection:RxSubscription) : void {
    unsafe {
        let state=rx_state(hub)
        // A teardown may already have connected a new generation. The failed
        // generation must not cancel it or its newly registered listeners.
        if(empty(state.data.connection.owner) || rx_control(state.data.connection)!=rx_control(connection)) {return}
        let subject=rx_state(state.data.subject)
        var observers:array<typedecl(subject.data.slots[0].observer) -const -&>
        for(slot in subject.data.slots) {observers |> emplace(rx_ref(slot.observer))}
        try {rx_unsubscribe(connection)} recover {}
        var index=0
        while(index<length(observers)) {try {rx_unsubscribe(rx_state(observers[index]).control)} recover {};index++}
        delete observers
    }
}

def private rx_publish_connect_retained(hub:tuple<tag:RxPublishTag;owner:iterator<auto?>;element:iterator<auto(T)>>) {
    unsafe {
        let state=rx_state(hub)
        if(!rx_is_closed(state.data.connection)) {
            var owner=rx_control(state.data.connection);owner.references++
            return <- RxSubscription(owner <- rx_subscription_lease(owner,true))
        }
        var connection <- rx_subscription()
        if(rx_state(state.data.subject).data.stopped) {rx_unsubscribe(connection);return <- connection}
        delete state.data.connection
        state.data.connection <- rx_subscription_ref(connection)
        var values <- rx_ref(hub);var errors <- rx_ref(hub);var completed <- rx_ref(hub)
        var active <- rx_subscription_ref(connection)
        var on_next <- @ capture(<-values,<-active) (value:T) {
            var failed=false;var message=""
            unsafe {try {rx_subject_next(rx_state(values).data.subject,value)} recover {failed=true;message="{this_context().last_exception}"}}
            if(failed) {rx_publish_abort(values,active);panic(message)}
        } finally {rx_finalize($ {delete active;delete values})}
        var on_error <- @ capture(<-errors) (message:string) {unsafe {rx_subject_error(rx_state(errors).data.subject,message)}} finally {rx_finalize($ {delete errors})}
        var on_complete <- @ capture(<-completed) () {unsafe {rx_subject_complete(rx_state(completed).data.subject)}} finally {rx_finalize($ {delete completed})}
        var failed=false;var message=""
        try {rx_subscribe_with(connection,state.data.source,on_next,on_error,on_complete)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {rx_publish_abort(hub,connection);delete connection;panic(message)}
        return <- connection
    }
}

def rx_connect(hub:tuple<tag:RxPublishTag;owner:iterator<auto?>;element:iterator<auto>>) {
    var retained <- rx_ref(hub)
    var connection:RxSubscription
    var failed=false;var message=""
    try {connection <- rx_publish_connect_retained(retained)} recover {failed=true;message="{this_context().last_exception}"}
    delete retained
    if(failed) {delete connection;panic(message)}
    return <- connection
}

def rx_connect(hub:tuple<tag:RxPublishTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {
    unsafe {rx_connect(rx_state(hub).data.subject,observer)}
}

def rx_ref_count(var hub:tuple<tag:RxPublishTag;owner:iterator<auto?>;element:iterator<auto(T)>>) {
    return <- rx_node(RxRefCountTag(),(hub <- hub),type<T>)
}

def private rx_publish_release(hub:auto) : void {
    unsafe {
        let state=rx_state(hub)
        state.data.listeners--
        if(state.data.listeners==0) {rx_unsubscribe(state.data.connection)}
    }
}

def rx_connect(source:tuple<tag:RxRefCountTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {
    unsafe {
        var hub <- rx_ref(rx_state(source).data.hub)
        let state=rx_state(hub)
        state.data.listeners++
        var retained <- rx_ref(hub)
        var cleanup <- @ capture(<-retained) () {rx_publish_release(retained)} finally {rx_finalize($ {delete retained})}
        var failed=false;var message=""
        try {
            rx_add_cleanup(rx_state(observer).control,cleanup)
            rx_connect(state.data.subject,observer)
            if(state.data.listeners>0 && rx_is_closed(state.data.connection) && !rx_stopped(observer)) {
                var connection <- rx_connect(hub)
                // A synchronous terminal may have closed every listener.
                if(!empty(state.data.connection.owner) && rx_control(connection)==rx_control(state.data.connection)) {
                    if(state.data.listeners==0) {rx_unsubscribe(connection)}
                    delete state.data.ref_connection
                    state.data.ref_connection <- connection
                } else {delete connection}
            }
        } recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {try {rx_unsubscribe(rx_state(observer).control)} recover {}}
        delete hub
        if(failed) {panic(message)}
    }
}

struct RxTerminalTag {_marker:uint8}
struct RxTerminalRunTag {_marker:uint8}

def private rx_terminal_node(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;seed:T;only_last:bool;emit_empty:bool;name:string) {
    var saved:T -const -& = seed
    static_if(typeinfo is_string(type<T>)) {saved=clone_string(seed)}
    return <- rx_node(RxTerminalTag(),(source <- source,seed=saved,only_last=only_last,emit_empty=emit_empty,name=name),type<T>)
}

def rx_last(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>) {return <- rx_terminal_node(source,default<T>,true,false,"rx_last")}

def rx_first(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>) {
    var first <- rx_take(source,1)
    return <- rx_terminal_node(first,default<T>,true,false,"rx_first")
}

def rx_default_if_empty(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;value:T) {return <- rx_terminal_node(source,value,false,true,"rx_default_if_empty")}

def rx_reduce(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;seed:auto(S);var reducer:lambda<(state:S;value:T):S>) {
    var resultSeed=seed
    var scan <- rx_scan(source,seed,reducer)
    return <- rx_terminal_node(scan,resultSeed,true,true,"rx_reduce")
}

def private rx_terminal_accept(run:auto;value:auto(T)) : void {
    unsafe {
        let state=rx_state(run)
        state.data.seen=true
        if(state.data.only_last) {
            clear(state.data.values)
            rx_group_push(state.data.values,value)
        } else {rx_next(state.data.observer,value)}
    }
}

def private rx_terminal_finish(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        if(!state.data.seen && !state.data.emit_empty) {rx_error(state.data.observer,"{state.data.name}: empty source");return}
        if(!state.data.seen || state.data.only_last) {
            var value=state.data.seed
            if(state.data.seen) {value=state.data.values[0]}
            rx_next(state.data.observer,value)
        }
        rx_done(state.data.observer)
    }
}

def rx_connect(source:tuple<tag:RxTerminalTag;owner:iterator<auto?>;element:iterator<auto(T)>>;observer:auto) : void {
    var values:array<T>
    // Snapshot a borrowed struct field before tuple construction (SDK JIT may
    // otherwise move it out of the reusable descriptor).
    var seed=rx_state(source).data.seed
    var run <- rx_node(RxTerminalRunTag(),(observer <- rx_ref(observer),values <- values,seed=seed,only_last=rx_state(source).data.only_last,
        emit_empty=rx_state(source).data.emit_empty,name=rx_state(source).data.name,seen=false),type<T>)
    var cleanupOwner <- rx_ref(run)
    var cleanup <- @ capture(<-cleanupOwner) () {unsafe {delete rx_state(cleanupOwner).data.values}} finally {rx_finalize($ {delete cleanupOwner})}
    var nextOwner <- rx_ref(run);var doneOwner <- rx_ref(run);var errorOwner <- rx_ref(observer)
    var on_next <- @ capture(<-nextOwner) (value:T) {rx_terminal_accept(nextOwner,value)} finally {rx_finalize($ {delete nextOwner})}
    var on_complete <- @ capture(<-doneOwner) () {rx_terminal_finish(doneOwner)} finally {rx_finalize($ {delete doneOwner})}
    var on_error <- @ capture(<-errorOwner) (message:string) {rx_error(errorOwner,message)} finally {rx_finalize($ {delete errorOwner})}
    var inner <- rx_observer(unsafe(rx_state(observer).control),on_next,on_error,on_complete,false)
    var failed=false;var message=""
    try {
        unsafe {rx_add_cleanup(rx_state(observer).control,cleanup)}
        unsafe {rx_connect(rx_state(source).data.source,inner)}
    } recover {failed=true;message="{this_context().last_exception}"}
    delete inner;delete run
    if(failed) {panic(message)}
}

// Sliding count/time groups. Window descriptors are borrowed notifications;
// rx_clone retains an inner Observable explicitly. Outer cancellation closes all
// open windows, removes timers, and disconnects the single source subscription.
struct RxSpanBufferTag {_marker:uint8}
struct RxSpanWindowTag {_marker:uint8}
struct RxSpanRunTag {_marker:uint8}
struct RxSpanFrameTag {_marker:uint8}

def private rx_span_node(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;tag:auto;
    count,stride:int;duration,period:int64;var clock:RxScheduler;output:type<auto(O)>) {
    rx_check_payload(type<T>)
    return <- rx_storage_node(tag,(source <- source,count=count,stride=stride,duration=duration,period=period,clock <- clock),type<O>)
}

def rx_buffer(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;count,skip:int) {
    if(count<=0 || skip<=0) {delete source;panic("rx_buffer: count and skip must be positive")}
    var clock:RxScheduler
    return <- rx_span_node(source,RxSpanBufferTag(),count,skip,0l,0l,clock,type<array<T>>)
}

def rx_window(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;count,skip:int) {
    if(count<=0 || skip<=0) {delete source;panic("rx_window: count and skip must be positive")}
    var clock:RxScheduler
    return <- rx_span_node(source,RxSpanWindowTag(),count,skip,0l,0l,clock,type<typedecl(rx_subject(type<T>)) -const -&>)
}

def rx_window(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;count:int) {return <- rx_window(source,count,count)}

def rx_buffer_time(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;duration_ms,period_ms:int|int64;scheduler:RxScheduler) {
    if(duration_ms<=0 || period_ms<=0) {delete source;panic("rx_buffer_time: duration and period must be positive")}
    var clock <- rx_scheduler_clone(scheduler)
    return <- rx_span_node(source,RxSpanBufferTag(),0,0,int64(duration_ms),int64(period_ms),clock,type<array<T>>)
}

def rx_window_time(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;duration_ms,period_ms:int|int64;scheduler:RxScheduler) {
    if(duration_ms<=0 || period_ms<=0) {delete source;panic("rx_window_time: duration and period must be positive")}
    var clock <- rx_scheduler_clone(scheduler)
    return <- rx_span_node(source,RxSpanWindowTag(),0,0,int64(duration_ms),int64(period_ms),clock,type<typedecl(rx_subject(type<T>)) -const -&>)
}

def rx_window_time(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;duration_ms:int|int64;scheduler:RxScheduler) {
    return <- rx_window_time(source,duration_ms,duration_ms,scheduler)
}

def private rx_span_frame(unused:type<auto(T)>;id:uint64;count:int) {
    var items:array<T -const -&>
    var subject:typedecl(rx_subject(type<T>)) -const -&
    return <- rx_storage_node(RxSpanFrameTag(),(items <- items,subject <- subject,id=id,remaining=count,timer=RxScheduledId(),closed=false),type<T>)
}

def private rx_span_emit_open(run,frame:auto;policy:RxSpanBufferTag) : void {}
def private rx_span_emit_open(run:auto;frame:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;policy:RxSpanWindowTag) : void {
    unsafe {
        let state=rx_state(frame)
        state.data.subject <- rx_subject(type<T>)
        rx_state(run).data.queue |> emplace((kind=0,value <- rx_ref(state.data.subject),error=""))
    }
    rx_serial_drain(run)
}

def private rx_span_end_frame(run,frame:auto;policy:RxSpanBufferTag;emit,failed:bool;message:string) : void {
    unsafe {
        let state=rx_state(frame)
        if(emit && !failed && !empty(state.data.items)) {
            var items <- state.data.items
            rx_state(run).data.queue |> emplace((kind=0,value <- items,error=""))
        } else {delete state.data.items}
    }
}

def private rx_span_end_frame(run,frame:auto;policy:RxSpanWindowTag;emit,failed:bool;message:string) : void {
    unsafe {
        let state=rx_state(frame)
        if(!empty(state.data.subject.owner)) {rx_subject_end(state.data.subject,failed,message)}
    }
}

def private rx_span_close_frame(run,frame:auto;emit:bool;failed:bool=false;message:string="") : void {
    unsafe {
        let state=rx_state(run);let item=rx_state(frame)
        if(item.data.closed) {return}
        item.data.closed=true
        // Detach before any user callback/finalizer can reenter.
        var index=0
        while(index<length(state.data.frames)) {
            if(rx_state(state.data.frames[index]).data.id==item.data.id) {
                var removed <- state.data.frames[index];state.data.frames |> erase(index);delete removed;break
            }
            index++
        }
        var cleanupFailed=false;var cleanupMessage=""
        if(state.data.duration>0) {
            var timer=item.data.timer;item.data.timer=RxScheduledId()
            try {rx_cancel(state.data.clock,timer)} recover {cleanupFailed=true;cleanupMessage="{this_context().last_exception}"}
        }
        try {rx_span_end_frame(run,frame,state.data.policy,emit,failed,message)} recover {if(!cleanupFailed) {cleanupFailed=true;cleanupMessage="{this_context().last_exception}"}}
        if(cleanupFailed) {panic(cleanupMessage)}
    }
}

def private rx_span_cancel(run:auto;flush:bool=false;error:bool=false;message:string="") : void {
    unsafe {
        let state=rx_state(run)
        state.data.stopped=true
        if(!flush || error) {delete state.data.queue}
        var frames <- state.data.frames
        var failed=false;var failure=""
        if(state.data.duration>0) {
            var opening=state.data.opening;state.data.opening=RxScheduledId()
            var lifecycle=state.data.lifecycle;state.data.lifecycle=RxScheduledId()
            try {rx_cancel(state.data.clock,opening)} recover {failed=true;failure="{this_context().last_exception}"}
            try {rx_cancel(state.data.clock,lifecycle)} recover {if(!failed) {failed=true;failure="{this_context().last_exception}"}}
        }
        try {rx_unsubscribe(state.data.child);rx_cleanup(rx_control(state.data.child))} recover {if(!failed) {failed=true;failure="{this_context().last_exception}"}}
        var index=0
        while(index<length(frames)) {
            try {rx_span_close_frame(run,frames[index],flush,error,message)} recover {if(!failed) {failed=true;failure="{this_context().last_exception}"}}
            index++
        }
        delete frames
        if(failed) {panic(failure)}
    }
}

def private rx_span_terminal(run:auto;error:bool;message:string="") : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        var failed=false;var failure=""
        try {rx_span_cancel(run,!error,error,message)} recover {failed=true;failure="{this_context().last_exception}"}
        if(failed && !error) {try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {};panic(failure)}
        var event:typedecl(state.data.queue[0]) -const -&
        event.kind=error ? 1 : 2;event.error=clone_string(message)
        state.data.queue |> emplace(event)
    }
    rx_serial_drain(run)
}

def private rx_span_open(run:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto>>;input:iterator<auto(T)>) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        if(state.data.serial==uint64(-1)) {rx_span_terminal(run,true,"rx window: IDs exhausted");return}
        state.data.serial++
        var frame <- rx_span_frame(type<T>,state.data.serial,state.data.count)
        state.data.frames |> emplace(rx_ref(frame))
        var failed=false;var message=""
        try {
            if(state.data.duration>0) {
                var owner <- rx_ref(run);var retained <- rx_ref(frame)
                var action <- @ capture(<-owner,<-retained) () {
                    unsafe {
                        let target=rx_state(owner)
                        if(target.data.stopped || rx_stopped(target.data.observer)) {return}
                        rx_state(retained).data.timer=RxScheduledId()
                    }
                    var failed=false;var message=""
                    try {rx_span_close_frame(owner,retained,true);rx_serial_drain(owner)} recover {failed=true;message="{this_context().last_exception}"}
                    if(failed) {unsafe {try {rx_unsubscribe(rx_state(rx_state(owner).data.observer).control)} recover {}};panic(message)}
                } finally {rx_finalize($ {delete retained;delete owner})}
                rx_state(frame).data.timer=rx_schedule(state.data.clock,state.data.duration,action)
            }
            rx_span_emit_open(run,frame,state.data.policy)
        } recover {failed=true;message="{this_context().last_exception}"}
        delete frame
        if(failed) {panic(message)}
    }
}

def private rx_span_arm(run:auto;input:iterator<auto(T)>) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        var owner <- rx_ref(run)
        var action <- @ capture(<-owner) () {
            unsafe {rx_state(owner).data.opening=RxScheduledId()}
            var failed=false;var message=""
            try {rx_span_open(owner,default<iterator<T>>);rx_span_arm(owner,default<iterator<T>>)} recover {failed=true;message="{this_context().last_exception}"}
            if(failed) {unsafe {if(rx_stopped(rx_state(owner).data.observer)) {panic(message)}};rx_span_terminal(owner,true,message)}
        } finally {rx_finalize($ {delete owner})}
        state.data.opening=rx_schedule(state.data.clock,state.data.period,action)
    }
}

def private rx_span_value(run,frame:auto;value:auto;policy:RxSpanBufferTag) : void {unsafe {rx_group_push(rx_state(frame).data.items,value)}}
def private rx_span_value(run,frame:auto;value:auto;policy:RxSpanWindowTag) : void {unsafe {rx_subject_next(rx_state(frame).data.subject,value)}}

def private rx_span_accept(run:auto;value:auto(T)) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        var snapshot:typedecl(state.data.frames) -const -&
        var index=0
        while(index<length(state.data.frames)) {snapshot |> emplace(rx_ref(state.data.frames[index]));index++}
        var failed=false;var message=""
        index=0
        try {
            while(index<length(snapshot) && !state.data.stopped && !rx_stopped(state.data.observer)) {
                let item=rx_state(snapshot[index])
                if(!item.data.closed) {
                    if(state.data.count>0) {item.data.remaining--}
                    rx_span_value(run,snapshot[index],value,state.data.policy)
                    if(state.data.count>0 && item.data.remaining==0) {rx_span_close_frame(run,snapshot[index],true)}
                }
                index++
            }
        } recover {failed=true;message="{this_context().last_exception}"}
        delete snapshot
        if(failed) {panic(message)}
        if(state.data.count>0 && !state.data.stopped && !rx_stopped(state.data.observer)) {
            state.data.until_open--
            if(state.data.until_open==0) {state.data.until_open=state.data.stride;rx_span_open(run,default<iterator<T>>)}
        }
    }
    rx_serial_drain(run)
}

def private rx_span_finished(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        rx_cleanup(rx_control(state.data.child))
    }
    rx_span_terminal(run,false)
}

def private rx_span_start(run:auto;source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>) : void {
    var values <- rx_ref(run);var errors <- rx_ref(run);var completed <- rx_ref(run)
    var on_next <- @ capture(<-values) (value:T) {
        var failed=false;var message=""
        try {rx_span_accept(values,value)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {unsafe {try {rx_unsubscribe(rx_state(rx_state(values).data.observer).control)} recover {}};panic(message)}
    } finally {rx_finalize($ {delete values})}
    var on_error <- @ capture(<-errors) (message:string) {rx_span_terminal(errors,true,message)} finally {rx_finalize($ {delete errors})}
    var on_complete <- @ capture(<-completed) () {
        unsafe {let target=rx_state(completed);target.data.done=true;if(!target.data.connecting) {rx_span_finished(completed)}}
    } finally {rx_finalize($ {delete completed})}
    unsafe {
        let state=rx_state(run)
        rx_subscribe_with(state.data.child,source,on_next,on_error,on_complete)
        state.data.connecting=false
        if(state.data.done) {rx_span_finished(run)}
    }
}

def private rx_span_connect(source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(O)>>;observer:auto;input:iterator<auto(T)>) : void {
    unsafe {
        let settings=rx_state(source)
        var frames:array<typedecl(rx_span_frame(type<T>,uint64(0),0)) -const -&>
        var queue:array<tuple<kind:int;value:O;error:string>>
        var clock:RxScheduler
        if(settings.data.duration>0) {clock <- rx_scheduler_clone(settings.data.clock)}
        var run <- rx_storage_node(RxSpanRunTag(),(source <- rx_ref(source),observer <- rx_ref(observer),child <- rx_subscription(),clock <- clock,
            frames <- frames,queue <- queue,policy=source.tag,count=settings.data.count,stride=settings.data.stride,duration=settings.data.duration,period=settings.data.period,
            until_open=0,serial=uint64(0),opening=RxScheduledId(),lifecycle=RxScheduledId(),stopped=false,dispatching=false,connecting=true,done=false),type<O>)
        var owner <- rx_ref(run)
        var cleanup <- @ capture(<-owner) () {rx_span_cancel(owner)} finally {rx_finalize($ {delete owner})}
        var failed=false;var message=""
        try {
            rx_add_cleanup(rx_state(observer).control,cleanup)
            let state=rx_state(run)
            if(state.data.duration>0) {
                var closing <- rx_ref(run)
                var action <- @ capture(<-closing) () {rx_span_terminal(closing,true,"rx scheduler closed")} finally {rx_finalize($ {delete closing})}
                state.data.lifecycle=rx_on_scheduler_close(state.data.clock,action)
                if(!state.data.stopped && !rx_stopped(observer)) {rx_span_open(run,input);rx_span_arm(run,input)}
            }
            if(state.data.count>0 && !state.data.stopped && !rx_stopped(observer)) {state.data.until_open=state.data.stride;rx_span_open(run,input)}
            if(!state.data.stopped && !rx_stopped(observer)) {rx_span_start(run,settings.data.source)}
        } recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {try {rx_unsubscribe(rx_state(observer).control)} recover {}}
        delete run
        if(failed) {panic(message)}
    }
}

def rx_connect(source:tuple<tag:RxSpanBufferTag|RxSpanWindowTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {
    unsafe {rx_span_connect(source,observer,rx_state(source).data.source.element)}
}

// Keyed hot streams. A group's descriptor owns only its key and Subject, never
// its parent subscription. Outer cancellation completes all remaining groups.
struct RxKeyGroupTag {_marker:uint8}
struct RxKeyedTag {_marker:uint8}
struct RxKeyedRunTag {_marker:uint8}

def private rx_keyed_group(key:auto(K);unused:type<auto(T)>) {
    rx_check_payload(type<K>)
    var saved=key
    static_if(typeinfo is_string(type<K>)) {saved=clone_string(key)}
    return <- rx_storage_node(RxKeyGroupTag(),(key <- saved,subject <- rx_subject(type<T>)),type<T>)
}

// Type marker, without allocation or a live source. Use it in callback signatures.
def rx_group_marker(key_type:type<auto(K)>;value_type:type<auto(T)>) {
    return <- default<typedecl(rx_keyed_group(default<K>,type<T>))>
}

def rx_group_key(group:tuple<tag:RxKeyGroupTag;owner:iterator<auto?>;element:iterator<auto>>) {
    unsafe {
        var key=rx_state(group).data.key
        static_if(typeinfo is_string(type<typedecl(key)>)) {return clone_string(key)}
        else {return <- key}
    }
}

def rx_connect(group:tuple<tag:RxKeyGroupTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {
    unsafe {rx_connect(rx_state(group).data.subject,observer)}
}

def rx_group_by(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>;var key_selector:lambda<(value:T):auto(K)>;max_groups:int=0) {
    if(max_groups<0) {delete source;unsafe {delete key_selector};panic("rx_group_by: max_groups must be nonnegative")}
    rx_check_payload(type<T>);rx_check_payload(type<K>)
    return <- rx_storage_node(RxKeyedTag(),(source <- source,key_selector <- key_selector,max_groups=max_groups),
        type<typedecl(rx_group_marker(type<K>,type<T>)) -const -&>)
}

def private rx_keyed_cancel(run:auto;error:bool=false;message:string="") : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped) {return}
        state.data.stopped=true
        // Detach storage before cleanup or terminal callbacks can reenter.
        var pending <- state.data.queue
        var groups <- state.data.groups
        var failed=false;var failure=""
        try {rx_unsubscribe(state.data.child);rx_cleanup(rx_control(state.data.child))} recover {failed=true;failure="{this_context().last_exception}"}
        var index=0
        while(index<length(groups)) {
            try {rx_subject_end(rx_state(groups[index]).data.subject,error,message)} recover {if(!failed) {failed=true;failure="{this_context().last_exception}"}}
            index++
        }
        try {delete pending} recover {if(!failed) {failed=true;failure="{this_context().last_exception}"}}
        try {delete groups} recover {if(!failed) {failed=true;failure="{this_context().last_exception}"}}
        if(failed) {panic(failure)}
    }
}

def private rx_keyed_terminal(run:auto;error:bool;message:string="") : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        rx_keyed_cancel(run,error,message)
        if(error) {rx_error(state.data.observer,message)} else {rx_done(state.data.observer)}
    }
}

def private rx_keyed_accept(run:auto;value:auto) : void {
    unsafe {
        let state=rx_state(run)
        var key:typedecl(invoke(rx_state(state.data.source).data.key_selector,value)) -const -&
        var failed=false;var message=""
        try {key=invoke(rx_state(state.data.source).data.key_selector,value)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {rx_queue_dispose(key);rx_keyed_terminal(run,true,message);return}
        var group:typedecl(state.data.groups[0]) -const -&
        try {
            if(!state.data.stopped && !rx_stopped(state.data.observer)) {
                var index=0
                while(index<length(state.data.groups)) {
                    var candidate <- rx_ref(state.data.groups[index])
                    var equal=false
                    var comparisonFailed=false;var comparisonMessage=""
                    try {equal=rx_state(candidate).data.key==key} recover {comparisonFailed=true;comparisonMessage="{this_context().last_exception}"}
                    if(equal && !comparisonFailed) {group <- candidate}
                    delete candidate
                    if(comparisonFailed) {rx_keyed_terminal(run,true,comparisonMessage);break}
                    if(equal || state.data.stopped || rx_stopped(state.data.observer)) {break}
                    index++
                }
                if(!state.data.stopped && !rx_stopped(state.data.observer)) {
                    if(empty(group.owner)) {
                        if(state.data.max_groups>0 && length(state.data.groups)>=state.data.max_groups) {
                            rx_keyed_terminal(run,true,"rx_group_by: group limit exceeded")
                        } else {
                            group <- rx_keyed_group(key,type<typedecl(value) -const -&>)
                            state.data.groups |> emplace(rx_ref(group))
                            rx_next(state.data.observer,group)
                        }
                    }
                    if(!state.data.stopped && !rx_stopped(state.data.observer)) {rx_subject_next(rx_state(group).data.subject,value)}
                }
            }
        } recover {failed=true;message="{this_context().last_exception}"}
        try {delete group} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        try {rx_queue_dispose(key)} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        if(failed) {panic(message)}
    }
}

// Serialize input as well as group announcements: even a custom rx_create
// producer reentering from the key selector/outer callback cannot overtake the
// first value of a just-announced group. No array foreach lock spans user code.
def private rx_keyed_drain(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.dispatching) {return}
        state.data.dispatching=true
        var failed=false;var message=""
        try {
            while(!state.data.stopped && !rx_stopped(state.data.observer) && !empty(state.data.queue)) {
                var event <- state.data.queue[0];state.data.queue |> erase(0)
                var eventFailed=false;var eventMessage=""
                try {
                    if(event.kind==0) {rx_keyed_accept(run,event.value)}
                    else {rx_keyed_terminal(run,event.kind==1,event.error)}
                } recover {eventFailed=true;eventMessage="{this_context().last_exception}"}
                try {rx_queue_dispose(event)} recover {if(!eventFailed) {eventFailed=true;eventMessage="{this_context().last_exception}"}}
                if(eventFailed) {panic(eventMessage)}
            }
        } recover {failed=true;message="{this_context().last_exception}"}
        state.data.dispatching=false
        if(failed) {
            try {rx_unsubscribe(rx_state(state.data.observer).control)} recover {}
            panic(message)
        }
    }
}

def private rx_keyed_end_input(run:auto;error:bool;message:string="") : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.stopped || rx_stopped(state.data.observer)) {return}
        var event:typedecl(state.data.queue[0]) -const -&
        event.kind=error ? 1 : 2;event.error=clone_string(message)
        state.data.queue |> emplace(event)
    }
    rx_keyed_drain(run)
}

def private rx_keyed_start(run:auto;source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>) : void {
    var values <- rx_ref(run);var errors <- rx_ref(run);var completed <- rx_ref(run)
    var on_next <- @ capture(<-values) (value:T) {
        unsafe {
            let state=rx_state(values)
            if(state.data.stopped || rx_stopped(state.data.observer)) {return}
            static_if(typeinfo is_string(type<T>)) {state.data.queue |> push((kind=0,value=clone_string(value),error=""))}
            else {state.data.queue |> push((kind=0,value=value,error=""))}
        }
        rx_keyed_drain(values)
    } finally {rx_finalize($ {delete values})}
    var on_error <- @ capture(<-errors) (message:string) {rx_keyed_end_input(errors,true,message)} finally {rx_finalize($ {delete errors})}
    var on_complete <- @ capture(<-completed) () {
        unsafe {let state=rx_state(completed);state.data.done=true;if(!state.data.connecting) {rx_keyed_end_input(completed,false)}}
    } finally {rx_finalize($ {delete completed})}
    unsafe {
        let state=rx_state(run)
        rx_subscribe_with(state.data.child,source,on_next,on_error,on_complete)
        state.data.connecting=false
        if(state.data.done) {rx_keyed_end_input(run,false)}
    }
}

def private rx_keyed_connect(source:tuple<tag:RxKeyedTag;owner:iterator<auto?>;element:iterator<auto(G)>>;observer:auto;input:iterator<auto(T)>) : void {
    var groups:array<G>
    var queue:array<tuple<kind:int;value:T;error:string>>
    var run <- rx_storage_node(RxKeyedRunTag(),(source <- rx_ref(source),observer <- rx_ref(observer),child <- rx_subscription(),groups <- groups,
        queue <- queue,max_groups=rx_state(source).data.max_groups,stopped=false,dispatching=false,connecting=true,done=false),type<G>)
    var owner <- rx_ref(run)
    var cleanup <- @ capture(<-owner) () {rx_keyed_cancel(owner)} finally {rx_finalize($ {delete owner})}
    var failed=false;var message=""
    unsafe {
        try {rx_add_cleanup(rx_state(observer).control,cleanup);rx_keyed_start(run,rx_state(source).data.source)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {try {rx_unsubscribe(rx_state(observer).control)} recover {}}
    }
    delete run
    if(failed) {panic(message)}
}

def rx_connect(source:tuple<tag:RxKeyedTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {
    unsafe {rx_keyed_connect(source,observer,rx_state(source).data.source.element)}
}

// A structural tagged union: terminal cases never construct/finalize a dummy T.
// The default value is a valid complete notification (the first, void case).
def rx_notification(unused:type<auto(T)>) {
    rx_check_payload(type<T>)
    return <- default<variant<complete;next:T -const -&;error:string>>
}

def rx_notification_next(value:auto(T)) : variant<complete;next:T -const -&;error:string> {
    rx_check_payload(type<T>)
    static_if(typeinfo is_string(type<T>)) {return variant<complete;next:T -const -&;error:string>(next=clone_string(value))}
    else {return variant<complete;next:T -const -&;error:string>(next=value)}
}

def rx_notification_error(message:string;unused:type<auto(T)>) : variant<complete;next:T -const -&;error:string> {
    rx_check_payload(type<T>)
    return variant<complete;next:T -const -&;error:string>(error=clone_string(message))
}

def rx_notification_complete(unused:type<auto(T)>) {return <- rx_notification(type<T>)}

struct RxMaterializeTag {_marker:uint8}
struct RxDematerializeTag {_marker:uint8}
struct RxNotificationRunTag {_marker:uint8}

def rx_materialize(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(T)>>) {
    return <- rx_node(RxMaterializeTag(),(source <- source),type<variant<complete;next:T -const -&;error:string>>)
}

def rx_dematerialize(var source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<variant<complete;next:auto(T);error:string>>>) {
    return <- rx_node(RxDematerializeTag(),(source <- source),type<T -const -&>)
}

def private rx_notification_cancel(run:auto) : void {
    unsafe {
        let state=rx_state(run)
        state.data.input_done=true
        // The root control closes upstream through its normal cleanup chain.
        // Drop captures even if an external producer still retains its sink.
        var queue <- state.data.queue;var source <- state.data.source
        var failed=false;var message=""
        try {delete queue} recover {failed=true;message="{this_context().last_exception}"}
        try {delete source} recover {if(!failed) {failed=true;message="{this_context().last_exception}"}}
        if(failed) {panic(message)}
    }
}

def private rx_notification_finish(run:auto;policy:RxMaterializeTag;error:bool;message:string="") : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.input_done || rx_stopped(state.data.observer)) {return}
        state.data.input_done=true
        var notice:typedecl(state.data.queue[0].value) -const -&
        if(error) {notice = variant type<typedecl(notice)>(error=clone_string(message))}
        // Queue both before invoking callbacks: reentrant sends cannot sneak
        // between the terminal notification and the actual completion.
        state.data.queue |> emplace((kind=0,value <- notice,error=""))
        var terminal:typedecl(state.data.queue[0]) -const -&
        terminal.kind=2;state.data.queue |> emplace(terminal)
    }
    rx_serial_drain(run)
}

def private rx_notification_finish(run:auto;policy:RxDematerializeTag;error:bool;message:string="") : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.input_done || rx_stopped(state.data.observer)) {return}
        state.data.input_done=true
        var terminal:typedecl(state.data.queue[0]) -const -&
        terminal.kind=error ? 1 : 2;terminal.error=clone_string(message)
        state.data.queue |> emplace(terminal)
    }
    rx_serial_drain(run)
}

def private rx_notification_accept(run:auto;value:auto;policy:RxMaterializeTag) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.input_done || rx_stopped(state.data.observer)) {return}
        var notice <- rx_notification_next(value)
        state.data.queue |> emplace((kind=0,value <- notice,error=""))
    }
    rx_serial_drain(run)
}

def private rx_notification_accept(run:auto;notice:variant<complete;next:auto(T);error:string>;policy:RxDematerializeTag) : void {
    unsafe {
        let state=rx_state(run)
        if(state.data.input_done || rx_stopped(state.data.observer)) {return}
        if(notice is next) {
            static_if(typeinfo is_string(type<T>)) {state.data.queue |> push((kind=0,value=clone_string(notice as next),error=""))}
            else {state.data.queue |> push((kind=0,value=notice as next,error=""))}
        } else {rx_notification_finish(run,policy,notice is error,notice is error ? notice as error : "");return}
    }
    rx_serial_drain(run)
}

def private rx_notification_connect(source:tuple<tag:auto;owner:iterator<auto?>;element:iterator<auto(O)>>;observer:auto;input:iterator<auto(I)>) : void {
    var queue:array<tuple<kind:int;value:O;error:string>>
    var run <- rx_node(RxNotificationRunTag(),(source <- rx_ref(source),observer <- rx_ref(observer),queue <- queue,input_done=false,dispatching=false),type<O>)
    var owner <- rx_ref(run)
    var cleanup <- @ capture(<-owner) () {rx_notification_cancel(owner)} finally {rx_finalize($ {delete owner})}
    var values <- rx_ref(run);var errors <- rx_ref(run);var completed <- rx_ref(run)
    var policy=source.tag
    var on_next <- @ capture(<-values,copy(policy)) (value:I) {rx_notification_accept(values,value,policy)} finally {rx_finalize($ {delete values})}
    var on_error <- @ capture(<-errors,copy(policy)) (message:string) {rx_notification_finish(errors,policy,true,message)} finally {rx_finalize($ {delete errors})}
    var on_complete <- @ capture(<-completed,copy(policy)) () {rx_notification_finish(completed,policy,false)} finally {rx_finalize($ {delete completed})}
    var inner <- rx_observer(unsafe(rx_state(observer).control),on_next,on_error,on_complete,false)
    var failed=false;var message=""
    unsafe {
        try {rx_add_cleanup(rx_state(observer).control,cleanup);rx_connect_inner(rx_state(source).data.source,inner)} recover {failed=true;message="{this_context().last_exception}"}
        if(failed) {try {rx_unsubscribe(rx_state(observer).control)} recover {}}
    }
    delete inner;delete run
    if(failed) {panic(message)}
}

def rx_connect(source:tuple<tag:RxMaterializeTag|RxDematerializeTag;owner:iterator<auto?>;element:iterator<auto>>;observer:auto) : void {
    unsafe {rx_notification_connect(source,observer,rx_state(source).data.source.element)}
}
