options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex_async_sequence.das
require ../../computation_expressions/lib/computation_macro.das
require daslib/rtti
var opened=0
var freed=0
var closed=0
var produced=0
var errors=0
var completed=0
var cleanups=0
var polling=false
var active:RxSubscription
struct Hold {
    data:array<int>
    def finalize {if(!empty(data)) {freed++;delete data}}
}
def hold() {opened++;return <- Hold(data <- [42])}
def tracked(input:auto;failClose:bool=false) {
    var view <- rx_clone(input)
    return <- rx_defer(@ capture(<-view,copy(failClose)) () {
        var data <- hold();var inner <- rx_clone(view)
        return <- rx_create(type<int>,@ capture(<-data,<-inner,copy(failClose)) (sink:typedecl(rx_sink_marker(type<int>))) {
            verify(data.data[0]==42)
            rx_sink_add_cleanup(sink,@ capture(copy(failClose)) () {cleanups++;if(failClose) {panic("close failed")}})
            rx_sink_add_cleanup(sink,@() {cleanups++})
            rx_connect(inner,sink)
        } finally {delete inner;delete data})
    } finally {delete view})
}
def to_checks() {
    for(policyId in range(3)) {
        let policy=policyId==0 ? RxOverflowPolicy.error : (policyId==1 ? RxOverflowPolicy.drop_oldest : RxOverflowPolicy.drop_latest)
        for(mode in range(7)) {
            var inscope input <- rx_subject(type<int>)
            var stream <- tracked(input,mode==6) |> rx_to_async_sequence(2,policy)
            var request <- async_sequence_next(stream)
            let before=cleanups
            if(mode==5) {
                delete request;delete stream
                verify(rx_subscriber_count(input)==0 && cleanups==before && opened==freed)
                continue
            }
            verify(task_poll(request)==TaskStatus.Waiting && rx_subscriber_count(input)==1)
            rx_subject_next(input,1);rx_subject_next(input,2)
            if(mode==0) {
                rx_subject_complete(input)
                verify(task_poll(request)==TaskStatus.Succeeded)
                var value <- task_take(request);verify(value is some && value as some==1)
                var next <- async_sequence_next(stream);verify(task_poll(next)==TaskStatus.Succeeded);delete next
                var done <- async_sequence_next(stream);verify(task_poll(done)==TaskStatus.Succeeded && task_value(done) is none);delete done
            } elif(mode==1 || mode==6) {
                task_cancel(request)
                verify(task_status(request)==(mode==6 ? TaskStatus.Failed : TaskStatus.Cancelled))
                delete request
            } elif(mode==2) {
                async_sequence_close(stream)
                verify(task_poll(request)==TaskStatus.Cancelled);delete request
            } elif(mode==3) {
                rx_subject_error(input,"source failed")
                verify(rx_subscriber_count(input)==0 && task_poll(request)==TaskStatus.Failed);delete request
            } else {
                rx_subject_next(input,3)
                verify(task_poll(request)==(policyId==0 ? TaskStatus.Failed : TaskStatus.Succeeded))
                delete request
            }
            delete stream
            verify(rx_subscriber_count(input)==0 && cleanups==before+2 && opened==freed)
        }
    }
    // A native connect failure releases the partially registered subscription.
    {
        var source <- rx_create(type<int>,@(sink:typedecl(rx_sink_marker(type<int>))) {
            rx_sink_add_cleanup(sink,@() {cleanups++})
            panic("connect failed")
        })
        var stream <- source |> rx_to_async_sequence(2)
        var request <- async_sequence_next(stream)
        let before=cleanups
        verify(task_poll(request)==TaskStatus.Failed && cleanups==before+1)
        delete request;delete stream
    }
}
struct Resource {data:array<int>;fail:bool}
def acquire(fail:bool) {opened++;return <- Resource(data <- [42],fail=fail)}
def ce_dispose(var resource:Resource) {
    verify(!polling && resource.data[0]==42)
    closed++;freed++;let fail=resource.fail;delete resource
    if(fail) {panic("producer close failed")}
}
def producer(mode:int) {
    return <- computation(AsyncSequenceBuilder()) {
        var resource & = acquire(mode==6) |> use_resource
        if(mode==7) {
            polling=true
            let before=closed
            rx_unsubscribe(active)
            verify(closed==before)
            polling=false
        }
        if(mode==12) {ce_task_cancelled();return}
        for(n in range(1,4)) {
            task_delay_ms(2) |> bind
            if(mode==4 || mode==9) {panic("producer failed")}
            produced++
            yield n
        }
    }
}
def from_checks() {
    for(mode in range(13)) {
        let oldErrors=errors;let oldDone=completed;let oldClosed=closed
        var inscope clock <- rx_virtual_scheduler()
        var data <- hold()
        var source <- @ capture(<-data,copy(mode)) () {verify(data.data[0]==42);return <- producer(mode)} finally {delete data} |> rx_from_async_sequence(clock)
        var callbackData <- hold()
        active <- rx_subscription()
        rx_subscribe_with(active,source,@ capture(<-callbackData,copy(mode)) (n:int) {
            verify(callbackData.data[0]==42)
            if(mode==5) {panic("observer failed")}
            if(mode==10) {rx_unsubscribe(active);verify(callbackData.data[0]==42)}
        } finally {delete callbackData},@ capture(copy(mode)) (s:string) {errors++;if(mode==9) {panic("error callback failed")}},
            @ capture(copy(mode)) () {completed++;if(mode==11) {panic("complete callback failed")}})
        delete source
        var caught=false
        try {
            if(mode==0 || mode==4 || mode==5 || mode==7 || mode==9 || mode==10 || mode==11 || mode==12) {rx_advance_to(clock,20)}
            elif(mode==1 || mode==6) {rx_advance_to(clock,0);rx_unsubscribe(active)}
            elif(mode==2) {rx_advance_to(clock,0);delete active}
            elif(mode==3) {rx_advance_to(clock,0);rx_scheduler_close(clock)}
            elif(mode==8) {rx_unsubscribe(active)}
        } recover {caught=true}
        verify(caught==(mode==5 || mode==6 || mode==9 || mode==11))
        if(mode!=2) {verify(rx_is_closed(active));delete active}
        verify(closed==oldClosed+(mode==8 ? 0 : 1) && opened==freed)
        verify(errors==oldErrors+((mode==3 || mode==4 || mode==9 || mode==12) ? 1 : 0))
        verify(completed==oldDone+((mode==0 || mode==11) ? 1 : 0))
        verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
    // Factory failure is an Rx error; no timer or producer survives it.
    {
        var inscope clock <- rx_virtual_scheduler()
        var source <- @() {
            if(true) {panic("factory failed")}
            return <- producer(0)
        } |> rx_from_async_sequence(clock)
        let before=errors
        var sub <- rx_subscribe(source,@(n:int) {},@(s:string) {errors++},@() {})
        verify(errors==before+1 && rx_is_closed(sub) && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
        delete sub;delete source
    }
}
def checks() {to_checks();from_checks();verify(opened==freed)}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline && opened==freed)
    print("ReactiveX AsyncSequence adapter lifetime checks OK\n")
}
