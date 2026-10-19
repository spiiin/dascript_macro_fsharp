options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti

var sum=0l
var trace=""
var late:RxSubscription
var released=0
struct Capture {
    items:array<int>
    def finalize {if(!empty(items)) {released++;delete items}}
}

def checks() {
    // The steady single-listener int/map path performs no heap allocations.
    {
        var inscope subject <- rx_subject(type<int>)
        var inscope pipeline <- rx_clone(subject) |> rx_map(@(n:int) {return n*3})
        var inscope sub <- rx_subscribe(pipeline,@(n:int) {sum+=int64(n)},@(e:string) {panic(e)},@() {})
        rx_subject_next(subject,1)
        let calls=heap_allocation_count()
        let bytes=heap_allocation_stats()[0]
        let before=sum
        for(i in range(1000)) {rx_subject_next(subject,i)}
        verify(sum-before==1498500l)
        verify(heap_allocation_count()==calls && heap_allocation_stats()[0]==bytes)
        rx_subject_complete(subject)
        verify(rx_is_closed(sub) && rx_subscriber_count(subject)==0)
    }
    // A new listener misses the current event, but sees queued events before
    // the queued completion. The optimization must not recurse into callbacks.
    trace=""
    {
        var inscope subject <- rx_subject(type<int>)
        var view <- rx_clone(subject)
        var inscope first <- rx_subscribe(subject,@ capture(<-view) (n:int) {
            trace+="A{n};"
            if(n==1) {
                late <- rx_subscribe(view,@(v:int) {trace+="B{v};"},@(e:string) {panic(e)},@() {trace+="Bc;"})
                rx_subject_next(view,2)
                rx_subject_complete(view)
                verify(trace=="A1;")
            }
        } finally {delete view},@(e:string) {panic(e)},@() {trace+="Ac;"})
        rx_subject_next(subject,1)
        verify(trace=="A1;A2;B2;Ac;Bc;" && rx_is_closed(first) && rx_is_closed(late))
        delete late
    }
    // Preserve the original observer error and drain reentrant events even
    // after removing the failing listener. Subsequent sends remain usable.
    trace=""
    {
        var inscope subject <- rx_subject(type<int>)
        var view <- rx_clone(subject)
        var inscope first <- rx_subscribe(subject,@ capture(<-view) (n:int) {
            trace+="A{n};"
            late <- rx_subscribe(view,@(v:int) {trace+="B{v};"},@(e:string) {panic(e)},@() {})
            rx_subject_next(view,2)
            panic("dispatch failure")
        } finally {delete view},@(e:string) {panic("must preserve native error")},@() {})
        var caught=false
        try {rx_subject_next(subject,1)} recover {caught=true}
        verify(caught && trace=="A1;B2;" && rx_is_closed(first) && !rx_is_closed(late))
        rx_subject_next(subject,3)
        verify(trace=="A1;B2;B3;")
        rx_subject_complete(subject)
        delete late
    }
    // Both public handles may disappear from inside a callback. The in-flight
    // observer and source stay alive until the callback has returned.
    {
        let previous=released
        var subject <- rx_subject(type<int>)
        var sub:RxSubscription
        var data <- Capture(items <- [42])
        unsafe {
            sub <- rx_subscribe(subject,@ capture(&subject,&sub,<-data) (n:int) {
                verify(data.items[0]==42)
                delete subject;delete sub
                verify(released==previous && data.items[0]==42)
            } finally {delete data},@(e:string) {panic(e)},@() {})
            rx_subject_next(subject,1)
        }
        verify(empty(subject.owner) && empty(sub.owner) && released==previous+1)
    }
    // Releasing the last in-flight observer runs captured finalizers while
    // dispatch is still paused. Their emissions follow the original callback.
    trace=""
    {
        var inscope subject <- rx_subject(type<int>)
        var first:RxSubscription
        var view <- rx_clone(subject)
        unsafe {
            first <- rx_subscribe(subject,@ capture(&first,<-view) (n:int) {
                trace+="A;"
                late <- rx_subscribe(view,@(v:int) {trace+="B{v};"},@(e:string) {panic(e)},@() {})
                rx_unsubscribe(first)
                verify(trace=="A;")
            } finally {rx_subject_next(view,9);delete view},@(e:string) {panic(e)},@() {})
            rx_subject_next(subject,1)
        }
        verify(trace=="A;B9;" && rx_is_closed(first))
        delete first;delete late
        verify(rx_subscriber_count(subject)==0)
    }
}

[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(5)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX Subject dispatch checks OK\n")
}
