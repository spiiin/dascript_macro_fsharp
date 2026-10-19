options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
require strings

var sum=0l
var completed=0
var trace=""
var victim:RxSubscription
var late:RxSubscription
var callbacks=0

def checks() {
    for(count in fixed_array(2,8,32)) {
        var inscope subject <- rx_subject(type<int>)
        var inscope pipeline <- rx_clone(subject) |> rx_map(@(n:int) {return n*3})
        var inscope subscriptions:array<RxSubscription>
        for(j in range(count)) {
            subscriptions |> emplace(rx_subscribe(pipeline,@(n:int) {sum+=int64(n)},@(e:string) {panic(e)},@() {completed++}))
        }
        rx_subject_next(subject,1) // Allocate the reusable snapshot once.
        let allocated=heap_allocation_count()
        let bytes=heap_allocation_stats()[0]
        let live=heap_bytes_allocated()
        let before=sum
        for(n in range(1000)) {rx_subject_next(subject,n)}
        verify(sum-before==1498500l*int64(count))
        verify(heap_allocation_count()==allocated && heap_allocation_stats()[0]==bytes && heap_bytes_allocated()==live)
        let done=completed
        rx_subject_complete(subject)
        verify(completed==done+count && rx_subscriber_count(subject)==0)
        for(sub in subscriptions) {verify(rx_is_closed(sub))}
    }
    // Unsubscribed observers are skipped, but their captures are retained until
    // every listener of the current snapshot has had its turn. Finalizers emit
    // behind already queued events. Newly added listeners start on event 2.
    trace=""
    {
        var inscope subject <- rx_subject(type<int>)
        var view <- rx_clone(subject)
        var inscope first <- rx_subscribe(subject,@ capture(<-view) (n:int) {
            trace+="A{n};"
            if(n==1) {
                rx_unsubscribe(victim)
                late <- rx_subscribe(view,@(v:int) {trace+="D{v};"},@(e:string) {panic(e)},@() {})
                rx_subject_next(view,2)
            }
        } finally {delete view},@(e:string) {panic(e)},@() {})
        var dying <- rx_clone(subject)
        victim <- rx_subscribe(subject,@ capture(<-dying) (n:int) {trace+="B{n};"} finally {trace+="Bf;";rx_subject_next(dying,9);delete dying},@(e:string) {panic(e)},@() {})
        var inscope third <- rx_subscribe(subject,@(n:int) {trace+="C{n};"},@(e:string) {panic(e)},@() {})
        rx_subject_next(subject,1)
        verify(trace=="A1;C1;Bf;A2;C2;D2;A9;C9;D9;")
        delete victim;delete late
        rx_subject_complete(subject)
    }
    // Multiple failures do not prevent later listeners or queued events from
    // running, and the first native exception is preserved.
    trace=""
    {
        var inscope subject <- rx_subject(type<int>)
        var view <- rx_clone(subject)
        var inscope first <- rx_subscribe(subject,@ capture(<-view) (n:int) {trace+="A;";rx_subject_next(view,2);panic("first fanout failure")} finally {delete view},@(e:string) {callbacks++},@() {})
        var inscope second <- rx_subscribe(subject,@(n:int) {trace+="B;";panic("second fanout failure")},@(e:string) {callbacks++},@() {})
        var inscope third <- rx_subscribe(subject,@(n:int) {trace+="C{n};"},@(e:string) {callbacks++},@() {})
        var caught=false
        try {rx_subject_next(subject,1)} recover {caught=find(string(this_context().last_exception),"first fanout failure")>=0}
        verify(caught && trace=="A;B;C1;C2;" && callbacks==0 && rx_subscriber_count(subject)==1)
        rx_subject_next(subject,3)
        verify(trace=="A;B;C1;C2;C3;")
        rx_subject_complete(subject)
    }
    // Growing slots from inside a callback must not invalidate the in-flight
    // snapshot. Later events use the new listener set and may grow the cache.
    {
        var inscope subject <- rx_subject(type<int>)
        var extra:array<RxSubscription>
        var view <- rx_clone(subject)
        unsafe {
            var inscope first <- rx_subscribe(subject,@ capture(<-view,&extra) (n:int) {
                sum+=int64(n)
                if(n==1) {
                    for(i in range(40)) {extra |> emplace(rx_subscribe(view,@(v:int) {sum+=int64(v)},@(e:string) {panic(e)},@() {}))}
                    rx_subject_next(view,2)
                }
            } finally {delete view},@(e:string) {panic(e)},@() {})
            var inscope second <- rx_subscribe(subject,@(n:int) {sum+=int64(n)},@(e:string) {panic(e)},@() {})
            let before=sum
            rx_subject_next(subject,1)
            verify(sum-before==86l)
            rx_subject_next(subject,3) // First direct send to 42 listeners.
            let calls=heap_allocation_count()
            rx_subject_next(subject,4)
            verify(heap_allocation_count()==calls)
            rx_subject_complete(subject)
            delete extra
        }
    }
    // Deleting the publisher during fan-out does not invalidate later turns.
    {
        var subject <- rx_subject(type<int>)
        unsafe {
            var inscope first <- rx_subscribe(subject,@ capture(&subject) (n:int) {delete subject},@(e:string) {panic(e)},@() {})
            var inscope second <- rx_subscribe(subject,@(n:int) {sum+=int64(n)},@(e:string) {panic(e)},@() {})
            let before=sum
            rx_subject_next(subject,7)
            verify(empty(subject.owner) && sum==before+7l)
        }
    }
}

[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(5)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX Subject fanout checks OK\n")
}
