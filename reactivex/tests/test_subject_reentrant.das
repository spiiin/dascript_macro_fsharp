options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
require strings

var sum=0l
var limit=3
var burst=false
var inCallback=false
var completed=0
var trace=""
var victim:RxSubscription
var late:RxSubscription
var released=0
struct Hold {
    items:array<int>
    def finalize {if(!empty(items)) {released++;delete items}}
}
def hold() {return <- Hold(items <- [42])}

def allocation_checks(count:int) {
    var inscope subject <- rx_subject(type<int>)
    var inscope pipeline <- rx_clone(subject) |> rx_map(@(n:int) {return n*2})
    var inscope subscriptions:array<RxSubscription>
    for(j in range(count)) {
        var view <- rx_clone(subject)
        subscriptions |> emplace(rx_subscribe(pipeline,@ capture(<-view,copy(j)) (value:int) {
            verify(!inCallback);inCallback=true
            sum+=int64(value)
            let n=value/2
            if(j==0) {
                if(burst && n%9==0) {for(offset in range(1,9)) {rx_subject_next(view,n+offset)}}
                elif(!burst && n<limit) {rx_subject_next(view,n+1)}
            }
            verify(inCallback);inCallback=false
        } finally {delete view},@(e:string) {panic(e)},@() {completed++}))
    }
    burst=false;limit=3
    rx_subject_next(subject,0) // Prepare queue capacity and reusable snapshot.
    var calls=heap_allocation_count()
    var bytes=heap_allocation_stats()[0]
    var live=heap_bytes_allocated()
    var before=sum
    limit=999
    rx_subject_next(subject,0)
    verify(sum-before==999000l*int64(count))
    verify(heap_allocation_count()==calls && heap_allocation_stats()[0]==bytes && heap_bytes_allocated()==live)
    burst=true
    rx_subject_next(subject,0) // Grow the queue to eight pending values.
    calls=heap_allocation_count();bytes=heap_allocation_stats()[0];live=heap_bytes_allocated();before=sum
    for(i in range(100)) {rx_subject_next(subject,i*9)}
    verify(sum-before==809100l*int64(count))
    verify(heap_allocation_count()==calls && heap_allocation_stats()[0]==bytes && heap_bytes_allocated()==live)
    let done=completed
    rx_subject_complete(subject)
    verify(completed==done+count && rx_subscriber_count(subject)==0)
    for(sub in subscriptions) {verify(rx_is_closed(sub))}
}

def checks() {
    for(count in fixed_array(1,8,32)) {allocation_checks(count)}
    trace=""
    {
        var inscope subject <- rx_subject(type<int>)
        var view <- rx_clone(subject)
        var inscope first <- rx_subscribe(subject,@ capture(<-view) (n:int) {
            trace+="A{n};"
            if(n==1) {rx_subject_next(view,2);rx_subject_next(view,3)}
            elif(n==2) {
                rx_unsubscribe(victim)
                late <- rx_subscribe(view,@(v:int) {trace+="D{v};"},@(e:string) {panic(e)},@() {trace+="Dc;"})
                rx_subject_next(view,4)
            } elif(n==5) {rx_subject_complete(view);rx_subject_next(view,6)}
        } finally {delete view},@(e:string) {panic(e)},@() {trace+="Ac;"})
        var dying <- rx_clone(subject)
        victim <- rx_subscribe(subject,@ capture(<-dying) (n:int) {trace+="B{n};"} finally {trace+="Bf;";rx_subject_next(dying,5);delete dying},@(e:string) {panic(e)},@() {panic("removed observer completed")})
        var inscope third <- rx_subscribe(subject,@(n:int) {trace+="C{n};"},@(e:string) {panic(e)},@() {trace+="Cc;"})
        rx_subject_next(subject,1)
        verify(trace=="A1;B1;C1;A2;C2;Bf;A3;C3;D3;A4;C4;D4;A5;C5;D5;Ac;Cc;Dc;")
        verify(rx_is_closed(first) && rx_is_closed(third) && rx_is_closed(late))
        delete victim;delete late
    }
    // Failures in queued notifications still finish the snapshot and FIFO.
    // Owning captures remain alive through C2, then are freed before C3.
    trace=""
    {
        let freedBefore=released
        var inscope subject <- rx_subject(type<int>)
        var view <- rx_clone(subject);var data <- hold()
        var inscope first <- rx_subscribe(subject,@ capture(<-view,<-data) (n:int) {
            verify(data.items[0]==42);trace+="A{n};"
            if(n==1) {rx_subject_next(view,2);rx_subject_next(view,3)}
            elif(n==2) {panic("first queued failure")}
        } finally {delete view;delete data},@(e:string) {panic("unexpected on_error")},@() {})
        var secondData <- hold()
        var inscope second <- rx_subscribe(subject,@ capture(<-secondData) (n:int) {
            verify(secondData.items[0]==42);trace+="B{n};";if(n==2) {panic("second queued failure")}
        } finally {delete secondData},@(e:string) {panic("unexpected on_error")},@() {})
        var thirdView <- rx_clone(subject);var thirdData <- hold()
        var inscope third <- rx_subscribe(subject,@ capture(<-thirdView,<-thirdData,copy(freedBefore)) (n:int) {
            verify(thirdData.items[0]==42);trace+="C{n};"
            if(n==2) {verify(released==freedBefore);rx_subject_next(thirdView,4)}
            elif(n>=3) {verify(released==freedBefore+2)}
        } finally {delete thirdView;delete thirdData},@(e:string) {panic("unexpected on_error")},@() {})
        var caught=false
        try {rx_subject_next(subject,1)} recover {caught=find(string(this_context().last_exception),"first queued failure")>=0}
        verify(caught && trace=="A1;B1;C1;A2;B2;C2;C3;C4;" && released==freedBefore+2)
        verify(rx_is_closed(first) && rx_is_closed(second) && !rx_is_closed(third))
        rx_subject_complete(subject)
        verify(released==freedBefore+3 && rx_subscriber_count(subject)==0)
    }
}

[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX Subject reentrant checks OK\n")
}
