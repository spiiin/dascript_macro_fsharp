options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
require daslib/rtti
require strings

var released:int[5]
var trace=""
var effects=0
struct Owned {
    id:int
    data:array<int>
    def finalize {if(!empty(data)) {released[id]++;delete data}}
}
def owned(id:int) {return <- Owned(id=id,data <- [42])}
def intact(before:int) {for(n in released) {verify(n==before)}}

def checks() {
    // Forwarded observers must retain control and every callback until the
    // in-flight frame finishes, even when the primary lease disappears.
    for(mode in range(8)) {
        trace=""
        let before=released[0]
        intact(before)
        var inscope subject <- rx_subject(type<int>)
        var a <- owned(0);var b <- owned(1)
        var source <- rx_clone(subject) |> rx_map(@ capture(<-a) (n:int) {
            verify(a.data[0]==42);return n*2
        } finally {delete a}) |> rx_filter(@ capture(<-b) (n:int) {
            verify(b.data[0]==42);return n>0
        } finally {delete b})
        var sub <- rx_subscription()
        rx_add_cleanup(sub,@ capture(copy(mode)) () {trace+="C1;";if(mode==7) {panic("cleanup failure")}})
        rx_add_cleanup(sub,@() {trace+="C2;"})
        var c <- owned(2);var d <- owned(3);var e <- owned(4)
        unsafe {
            rx_subscribe_with(sub,source,@ capture(&source,&sub,<-c,copy(mode),copy(before)) (n:int) {
                verify(n==2 && c.data[0]==42)
                trace+="N;";delete source
                if(mode==2 || mode==7) {rx_unsubscribe(sub)}
                elif(mode==3) {delete sub}
                elif(mode==4) {panic("next failure")}
                intact(before);verify(c.data[0]==42);trace+="after;"
            } finally {delete c},@ capture(&source,&sub,<-d,copy(mode),copy(before)) (message:string) {
                verify(message=="upstream" && d.data[0]==42)
                trace+="E;";delete source
                if(mode==6) {delete sub;panic("error failure")}
                intact(before);verify(d.data[0]==42);trace+="after;"
            } finally {delete d},@ capture(&source,&sub,<-e,copy(mode),copy(before)) () {
                verify(e.data[0]==42)
                trace+="D;";delete source
                if(mode==5) {delete sub;panic("complete failure")}
                intact(before);verify(e.data[0]==42);trace+="after;"
            } finally {delete e})
        }
        var caught=false
        try {
            if(mode==0 || mode==5) {rx_subject_complete(subject)}
            elif(mode==1 || mode==6) {rx_subject_error(subject,"upstream")}
            else {rx_subject_next(subject,1)}
        } recover {
            caught=true
            let message="{this_context().last_exception}"
            verify(starts_with(message,mode==4 ? "next failure" : mode==5 ? "complete failure" : mode==6 ? "error failure" : "cleanup failure"))
        }
        verify(caught==(mode>=4))
        if(mode==0) {verify(trace=="D;after;C1;C2;")}
        elif(mode==1) {verify(trace=="E;after;C1;C2;")}
        elif(mode==2 || mode==3) {verify(trace=="N;C1;C2;after;")}
        elif(mode==5) {verify(trace=="D;C1;C2;")}
        elif(mode==6) {verify(trace=="E;C1;C2;")}
        else {verify(trace=="N;C1;C2;")}
        verify(rx_subscriber_count(subject)==0 && empty(source.owner))
        if(mode==3 || mode==5 || mode==6) {verify(empty(sub.owner))}
        else {verify(rx_is_closed(sub) && !rx_unsubscribe(sub))}
        for(n in released) {verify(n==before+1)}
        delete sub;delete source
        rx_subject_next(subject,2)
    }
    // Native break/continue flags must not skip destruction of inline refs.
    let initial=effects
    var inscope source <- rx_range(1,2) |> rx_map(@(n:int) {return n*3}) |> rx_filter(@(n:int) {return n>0})
    for(i in range(10)) {
        var inscope sub <- rx_subscribe(source,@(n:int) {effects+=n},@(e:string) {panic(e)},@() {})
        if(i==4) {break}
        continue
    }
    verify(effects==initial+45)
}
// Errors in a selector/predicate may delete the whole public pipeline.
// Its captures must survive both terminal delivery and a throwing error callback.
var handler_released=0
struct HandlerCapture {
    data:array<int>
    def finalize {if(!empty(data)) {handler_released++;delete data}}
}
def handler_checks() {
    for(mode in range(4)) {
        let before=handler_released
        var inscope subject <- rx_subject(type<int>)
        var a <- HandlerCapture(data <- [42])
        var b <- HandlerCapture(data <- [42])
        var pipeline <- rx_clone(subject) |> rx_map(@ capture(<-a,copy(mode)) (n:int) {
            verify(a.data[0]==42)
            if(mode%2==0) {panic("map failed")}
            return n
        } finally {delete a}) |> rx_filter(@ capture(<-b) (n:int) {
            verify(b.data[0]==42);panic("filter failed");return true
        } finally {delete b})
        var calls=0
        unsafe {
            var inscope sub <- rx_subscribe(pipeline,@(n:int) {panic("unexpected next")},
                @ capture(&pipeline,&calls,copy(before),copy(mode)) (message:string) {
                    calls++
                    verify(starts_with(message,mode%2==0 ? "map failed" : "filter failed"))
                    delete pipeline
                    verify(handler_released==before)
                    if(mode>=2) {panic("terminal failed")}
                },@() {panic("unexpected complete")})
            var caught=false
            try {rx_subject_next(subject,1)} recover {
                caught=true;verify(starts_with("{this_context().last_exception}","terminal failed"))
            }
            verify(caught==(mode>=2) && calls==1 && rx_is_closed(sub))
        }
        verify(handler_released==before+2 && rx_subscriber_count(subject)==0)
        delete pipeline
    }
}

[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {checks();handler_checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX subscription ownership checks OK\n")
}
