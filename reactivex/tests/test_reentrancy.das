options gen2
options max_infer_passes=512
require ../lib/reactivex.das
require daslib/rtti
var trace=""
var inCallback=false
var bValues=0
var bDone=0
var other:RxSubscription
var late:RxSubscription

def checks() {
    trace=""
    {
        var inscope source <- rx_subject(type<int>)
        var view <- rx_clone(source)
        var inscope a <- rx_subscribe(source,@ capture(<-view) (n:int) {
            verify(!inCallback);inCallback=true
            trace+="A{n};"
            if(n==1) {rx_subject_next(view,2)}
            if(n==2) {rx_subject_complete(view)}
            verify(inCallback);inCallback=false
        } finally {delete view},@(message:string) {panic(message)},@(){trace+="Ac;"})
        var inscope b <- rx_subscribe(source,@(n:int) {verify(!inCallback);trace+="B{n};"},@(message:string) {panic(message)},@(){trace+="Bc;"})
        rx_subject_next(source,1)
        verify(trace=="A1;B1;A2;B2;Ac;Bc;" && rx_subscriber_count(source)==0)
        verify(rx_is_closed(a) && rx_is_closed(b))
        var inscope terminal <- rx_subscribe(source,@(n:int) {panic("unexpected replay")},@(message:string) {panic(message)},@(){trace+="late;"})
        verify(rx_is_closed(terminal) && trace=="A1;B1;A2;B2;Ac;Bc;late;")
    }
    // Removing a subscriber during emission skips its turn. A subscriber added
    // during emission starts on the next notification, not on the current one.
    trace=""
    {
        var inscope source <- rx_subject(type<int>)
        var view <- rx_clone(source)
        var inscope a <- rx_subscribe(source,@ capture(<-view) (n:int) {
            trace+="A{n};"
            if(n==1) {
                rx_unsubscribe(other)
                late <- rx_subscribe(view,@(value:int) {trace+="C{value};"},@(message:string) {panic(message)},@(){})
            }
        } finally {delete view},@(message:string) {panic(message)},@(){})
        other <- rx_subscribe(source,@(n:int) {trace+="B{n};"},@(message:string) {panic(message)},@(){})
        rx_subject_next(source,1)
        rx_subject_next(source,2)
        verify(trace=="A1;A2;C2;" && rx_subscriber_count(source)==2)
        rx_subject_complete(source)
        delete other;delete late
    }
    // A broken observer is detached, other observers still receive the event,
    // and a caught publisher exception does not wedge the dispatch queue.
    {
        var inscope source <- rx_subject(type<int>)
        let previous=bValues
        let done=bDone
        var inscope broken <- rx_subscribe(source,@(n:int) {panic("observer failed")},@(message:string) {},@(){})
        var inscope good <- rx_subscribe(source,@(n:int) {bValues+=n},@(message:string) {},@(){bDone++})
        var caught=false
        try {rx_subject_next(source,1)} recover {caught=true}
        verify(caught && rx_is_closed(broken) && !rx_is_closed(good) && bValues==previous+1)
        rx_subject_next(source,2);rx_subject_complete(source)
        verify(bValues==previous+3 && bDone==done+1 && rx_subscriber_count(source)==0)
    }
    // Callback finalizers can emit while a listener is being detached. The
    // removed slot must be absent before any user-owned capture is finalized.
    {
        var inscope source <- rx_subject(type<int>)
        var view <- rx_clone(source)
        let previous=bValues
        var inscope a <- rx_subscribe(source,@ capture(<-view) (n:int) {} finally {rx_subject_next(view,9);delete view},@(message:string) {},@(){})
        var inscope b <- rx_subscribe(source,@(n:int) {bValues+=n},@(message:string) {},@(){})
        rx_unsubscribe(a)
        verify(bValues==previous+9 && rx_subscriber_count(source)==1)
        rx_unsubscribe(b)
    }
    // The emission retains the source even if a callback deletes its original
    // handle. This borrowed test capture cannot escape the local scope.
    {
        var source <- rx_subject(type<int>)
        unsafe {
            var inscope sub <- rx_subscribe(source,@ capture(&source) (n:int) {delete source},@(message:string) {},@(){})
            rx_subject_next(source,1)
            verify(empty(source.owner))
            rx_unsubscribe(sub)
        }
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(20)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX reentrancy checks OK\n")
}
