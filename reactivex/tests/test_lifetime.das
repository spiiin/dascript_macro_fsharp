options gen2
options max_infer_passes=512
require ../lib/reactivex.das
require daslib/rtti
require daslib/strings_boost
var sum=0
var completed=0
var errors=0
var cleaned=0
var callbacks=0
var factories=0
var tested=0
struct Resource {
    data:array<int>
    def finalize {if(!empty(data)) {cleaned++;delete data}}
}
def cleanup_action(fail:bool=false) {
    var inscope resource:Resource
    resource.data <- [1,2,3]
    return <- @ capture(<-resource,copy(fail)) () {
        verify(length(resource.data)==3)
        callbacks++
        if(fail) {panic("cleanup failed")}
    } finally {delete resource}
}
def subscribe_count(source:auto) {
    return <- rx_subscribe(source,@(n:int) {sum+=n},@(message:string) {errors++},@(){completed++})
}
def checks() {
    let before=cleaned
    let calls=callbacks
    // Owner destruction cancels and detaches an active hot subscription.
    {
        var inscope subject <- rx_subject(type<int>)
        {
            var inscope pipeline <- rx_clone(subject) |> rx_map(@(n:int) {return n+1})
            var inscope subscription <- subscribe_count(pipeline)
            rx_add_cleanup(subscription,cleanup_action())
            verify(rx_subscriber_count(subject)==1)
            // Subscriptions retain their callbacks and pipeline data.
            delete pipeline
            rx_subject_next(subject,2)
        }
        verify(rx_subscriber_count(subject)==0 && cleaned==before+1 && callbacks==calls+1)
        rx_subject_next(subject,100)
    }
    // Cleanup is exactly once, even if attached after synchronous completion.
    {
        var inscope source <- rx_range(1,1)
        var inscope subscription <- subscribe_count(source)
        rx_add_cleanup(subscription,cleanup_action())
        verify(cleaned==before+2 && callbacks==calls+2)
        verify(!rx_unsubscribe(subscription))
    }
    // All cleanup actions run and release captures when the first action fails.
    {
        var inscope subscription <- rx_subscription()
        rx_add_cleanup(subscription,cleanup_action(true))
        rx_add_cleanup(subscription,cleanup_action())
        var caught=false
        try {rx_unsubscribe(subscription)} recover {caught=true}
        verify(caught && rx_is_closed(subscription) && callbacks==calls+4 && cleaned==before+4)
        verify(!rx_unsubscribe(subscription))
    }
    // A subscription allocated before connecting can stop a synchronous source.
    {
        var inscope source <- rx_range(0,10)
        var inscope subscription <- rx_subscription()
        let start=tested
        // Reference capture is scoped: this source completes synchronously.
        unsafe {rx_subscribe_with(subscription,source,@ capture(&subscription) (n:int) {tested++;rx_unsubscribe(subscription)},@(message:string) {panic(message)},@(){completed++})}
        verify(tested==start+1 && rx_is_closed(subscription))
    }
    // User callback exceptions dispose the subscription and propagate to emit.
    {
        var inscope subject <- rx_subject(type<int>)
        var inscope subscription <- rx_subscribe(subject,@(n:int) {panic("consumer failed")},@(message:string) {errors++},@(){completed++})
        rx_add_cleanup(subscription,cleanup_action())
        var caught=false
        try {rx_subject_next(subject,1)} recover {caught=true}
        verify(caught && rx_is_closed(subscription) && rx_subscriber_count(subject)==0 && cleaned==before+5)
    }
    // A producer/operator error is delivered through on_error instead.
    {
        var inscope subject <- rx_subject(type<int>)
        var inscope pipeline <- rx_clone(subject) |> rx_map(@(n:int) {panic("selector failed");return n})
        let oldErrors=errors
        var inscope subscription <- subscribe_count(pipeline)
        rx_add_cleanup(subscription,cleanup_action())
        rx_subject_next(subject,1)
        verify(rx_is_closed(subscription) && rx_subscriber_count(subject)==0 && errors==oldErrors+1 && cleaned==before+6)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(30)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX lifetime checks OK\n")
}
