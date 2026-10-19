options gen2
options max_infer_passes=1024
options stack=524288
require ../lib/reactivex.das
require daslib/rtti
var opened=0
var freed=0
var cleaned=0
var done=0
var errors=0
var values=0
var finalized=0
struct Hold {
    data:array<int>
    def finalize {if(!empty(data)) {freed++;delete data}}
}
struct Payload {n:int;def finalize {finalized++}}
def hold() {opened++;return <- Hold(data <- [42])}
def tracked(source:auto) {
    var view <- rx_clone(source)
    return <- rx_defer(@ capture(<-view) () {
        var h <- hold()
        return <- rx_clone(view) |> rx_tap(@ capture(<-h) (n:int){verify(h.data[0]==42)} finally {delete h})
    } finally {delete view})
}
def checks() {
    for(mode in range(2)) {
        for(caseId in range(9)) {
            values=0;done=0;errors=0
            var inscope input <- rx_subject(type<int>)
            var source <- tracked(input) |> rx_materialize() |> rx_take(mode==0 ? 100 : 1)
            var control <- rx_subscription();let pointer=unsafe(addr(control))
            rx_subscribe_with(control,source,@ capture(copy(caseId),copy(pointer)) (e:typedecl(rx_notification(type<int>))) {
                values++
                if(caseId==3) {panic("notification callback failed")}
                if(caseId==4) {unsafe {rx_unsubscribe(*pointer)}}
            },@(s:string){errors++},@ capture(copy(caseId)) (){done++;if(caseId==5){panic("complete callback failed")}})
            delete source
            if(caseId==6) {rx_add_cleanup(control,@(){cleaned++;panic("teardown failed")})}
            var caught=false
            try {
                if(caseId==0) {rx_unsubscribe(control)}
                elif(caseId==1) {delete control}
                elif(caseId==2 || caseId==6) {rx_subject_error(input,"source")}
                elif(caseId==5 || caseId==7) {rx_subject_complete(input)}
                else {rx_subject_next(input,1);if(caseId==8) {rx_subject_complete(input)}}
            } recover {caught=true}
            verify(caught==(caseId==3 || caseId==5 || caseId==6))
            if(caseId!=1) {verify(rx_is_closed(control))}
            verify(errors==0 && rx_subscriber_count(input)==0 && opened==freed)
            if(caseId==0 || caseId==1 || caseId==3 || caseId==4) {verify(done==0)}
            delete control
        }
    }
    // The decoder also forwards real errors, closes on encoded terminals, and
    // releases observer captures when next/error/complete callbacks throw.
    for(caseId in range(8)) {
        var inscope input <- rx_subject(type<typedecl(rx_notification(type<int>))>)
        var source <- rx_clone(input) |> rx_dematerialize()
        var resource <- hold()
        var control <- rx_subscription();let pointer=unsafe(addr(control))
        rx_subscribe_with(control,source,@ capture(<-resource,copy(caseId),copy(pointer)) (n:int) {
            verify(resource.data[0]==42)
            if(caseId==3) {panic("next callback failed")}
            if(caseId==4) {unsafe {rx_unsubscribe(*pointer)}}
        } finally {delete resource},@ capture(copy(caseId)) (s:string){if(caseId==5){panic("error callback failed")}},
            @ capture(copy(caseId)) (){if(caseId==6){panic("complete callback failed")}})
        delete source
        var caught=false
        try {
            if(caseId==0) {rx_unsubscribe(control)}
            elif(caseId==1) {delete control}
            elif(caseId==2 || caseId==5) {rx_subject_next(input,rx_notification_error("encoded",type<int>))}
            elif(caseId==6) {rx_subject_next(input,rx_notification_complete(type<int>))}
            elif(caseId==7) {rx_subject_error(input,"upstream")}
            else {rx_subject_next(input,rx_notification_next(1))}
        } recover {caught=true}
        verify(caught==(caseId==3 || caseId==5 || caseId==6))
        if(caseId!=1) {verify(rx_is_closed(control))}
        verify(rx_subscriber_count(input)==0 && opened==freed);delete control
    }
    // Terminal notifications have no dummy Payload to destroy.
    finalized=0
    {
        var inscope source <- rx_empty(type<Payload>) |> rx_materialize()
        var inscope sub <- rx_subscribe(source,@(e:typedecl(rx_notification(type<Payload>))){verify(e is complete)},@(s:string){panic(s)},@(){})
        verify(finalized==0 && rx_is_closed(sub))
    }
    // Pending next values inside a notification are destroyed on unsubscribe.
    {
        var inscope clock <- rx_virtual_scheduler()
        var inscope input <- rx_subject(type<Payload>)
        var inscope source <- rx_clone(input) |> rx_materialize() |> rx_observe_on(clock)
        var inscope sub <- rx_subscribe(source,@(e:typedecl(rx_notification(type<Payload>))){panic("cancelled")},@(s:string){panic(s)},@(){})
        rx_subject_next(input,Payload(n=7))
        let before=finalized;rx_unsubscribe(sub)
        verify(finalized>before && rx_subscriber_count(input)==0 && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline && opened==freed)
    print("ReactiveX notification lifetime tests OK\n")
}
