options gen2
options max_infer_passes=1024
options stack=524288
require ../lib/reactivex.das
require daslib/rtti
var opened=0
var freed=0
var completed=0
var errors=0
var received=0
var finalized:int[5]
var subscriptions:array<RxSubscription>
var groups:array<typedecl(rx_group_marker(type<int>,type<int>))>
struct Hold {
    values:array<int>
    def finalize {if(!empty(values)) {freed++;delete values}}
}
struct Payload {
    n:int
    def finalize {if(n>0 && n<5) {finalized[n]++}}
}
def hold() {opened++;return <- Hold(values <- [42])}
def tracked(source:auto) {
    var view <- rx_clone(source)
    return <- rx_defer(@ capture(<-view) () {
        var resource <- hold()
        return <- rx_clone(view) |> rx_tap(@ capture(<-resource) (n:int) {verify(resource.values[0]==42)} finally {delete resource})
    } finally {delete view})
}
def checks() {
    // Invalid settings also dispose the moved descriptor and selector captures.
    {
        var data <- hold()
        var caught=false
        try {
            var inscope invalid <- rx_range(1,3) |> rx_group_by(@ capture(<-data) (n:int){return n} finally {delete data},-1)
        } recover {caught=true}
        verify(caught && opened==freed)
    }
    for(caseId in range(12)) {
        completed=0;errors=0;received=0
        var inscope input <- rx_subject(type<int>)
        var selector <- hold()
        var source <- tracked(input) |> rx_group_by(@ capture(<-selector,copy(caseId)) (n:int) {
            verify(selector.values[0]==42)
            if(caseId==5 && n==3) {panic("key selector failed")}
            return n%2
        } finally {delete selector})
        var control <- rx_subscription()
        let pointer=unsafe(addr(control))
        rx_subscribe_with(control,source,@ capture(copy(caseId),copy(pointer)) (g:typedecl(rx_group_marker(type<int>,type<int>))) {
            groups |> emplace(rx_clone(g))
            subscriptions |> emplace(rx_subscribe(g,@ capture(copy(caseId),copy(pointer)) (n:int) {
                received++
                if(caseId==6 && n==3) {panic("group next failed")}
                if(caseId==11) {unsafe {rx_unsubscribe(*pointer)}}
            },@ capture(copy(caseId)) (message:string) {errors++;if(caseId==8) {panic("group error failed")}},
                @ capture(copy(caseId)) () {completed++;if(caseId==7) {panic("group complete failed")}}))
            if(caseId==10) {unsafe {rx_unsubscribe(*pointer)}}
        },@(message:string) {errors++},@(){completed++})
        delete source
        if(caseId==9) {rx_add_cleanup(control,@(){panic("teardown failed")})}
        var caught=false
        try {
            rx_subject_next(input,1)
            if(caseId!=10 && caseId!=11) {
                rx_subject_next(input,2)
                if(caseId==1 || caseId==8) {rx_subject_error(input,"upstream")}
                elif(caseId==2 || caseId==9) {rx_unsubscribe(control)}
                elif(caseId==3) {delete control}
                elif(caseId==4) {
                    rx_unsubscribe(subscriptions[0]);rx_subject_next(input,3)
                    verify(rx_subscriber_count(input)==1);rx_subject_complete(input)
                } else {rx_subject_next(input,3);rx_subject_complete(input)}
            }
        } recover {caught=true}
        verify(caught==(caseId==6 || caseId==7 || caseId==8 || caseId==9))
        if(caseId!=3) {verify(rx_is_closed(control))}
        verify(rx_subscriber_count(input)==0 && opened==freed)
        for(listener in subscriptions) {verify(rx_is_closed(listener))}
        if(caseId==1) {verify(errors==3 && completed==0)}
        if(caseId==0) {verify(completed==3 && errors==0)}
        if(caseId==4) {verify(completed==2 && received==2 && errors==0)}
        if(caseId==10) {verify(received==0 && completed==1)}
        if(caseId==11) {verify(received==1 && completed==1)}
        // Saved groups do not retain the source or key selector after cancellation.
        for(g in groups) {verify(rx_group_key(g)==0 || rx_group_key(g)==1)}
        delete control;delete subscriptions;delete groups
        verify(opened==freed)
    }
    // Exceptions from the outer group callback close previously announced groups.
    {
        completed=0
        var inscope input <- rx_subject(type<int>)
        var source <- tracked(input) |> rx_group_by(@(n:int){return n})
        var inscope control <- rx_subscribe(source,@(g:typedecl(rx_group_marker(type<int>,type<int>))) {
            subscriptions |> emplace(rx_subscribe(g,@(n:int){},@(s:string){},@(){completed++}))
            if(rx_group_key(g)==2) {panic("outer callback failed")}
        },@(s:string){},@(){})
        delete source
        rx_subject_next(input,1)
        var caught=false
        try {rx_subject_next(input,2)} recover {caught=true}
        verify(caught && completed==2 && rx_is_closed(control) && rx_subscriber_count(input)==0 && opened==freed)
        delete subscriptions
    }
    // No group callback may keep the synchronous source running after cancellation.
    for(stage in range(2)) {
        received=0;completed=0
        var inscope control <- rx_subscription()
        let pointer=unsafe(addr(control))
        var inscope source <- rx_range(1,10) |> rx_tap(@(n:int){received++}) |> rx_group_by(@(n:int){return n%2})
        rx_subscribe_with(control,source,@ capture(copy(stage),copy(pointer)) (g:typedecl(rx_group_marker(type<int>,type<int>))) {
            subscriptions |> emplace(rx_subscribe(g,@ capture(copy(stage),copy(pointer)) (n:int){if(stage==1) {unsafe {rx_unsubscribe(*pointer)}}},@(s:string){},@(){completed++}))
            if(stage==0) {unsafe {rx_unsubscribe(*pointer)}}
        },@(s:string){},@(){panic("outer cancellation has no complete")})
        verify(received==1 && completed==1 && rx_is_closed(control));delete subscriptions
    }
    // Owning values are released on normal delivery and on failure in a group.
    for(mode in range(3)) {
        for(i in range(5)) {finalized[i]=0}
        var inscope input <- rx_subject(type<Payload>)
        var source <- rx_clone(input) |> rx_group_by(@ capture(copy(mode)) (p:Payload){if(mode==1){panic("key")};return p.n%2})
        var inscope sub <- rx_subscribe(source,@ capture(copy(mode)) (g:typedecl(rx_group_marker(type<int>,type<Payload>))) {
            subscriptions |> emplace(rx_subscribe(g,@ capture(copy(mode)) (p:Payload){if(mode==2){panic("consumer")}},@(s:string){},@(){}))
        },@(s:string){},@(){})
        delete source
        var caught=false
        try {rx_subject_next(input,Payload(n=1))} recover {caught=true}
        verify(caught==(mode==2) && finalized[1]>0)
        rx_unsubscribe(sub)
        verify(rx_subscriber_count(input)==0);delete subscriptions
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline && opened==freed)
    print("ReactiveX group_by lifetime tests OK\n")
}
