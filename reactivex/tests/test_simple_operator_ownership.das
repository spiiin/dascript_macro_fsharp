options gen2
options max_infer_passes=2048
require ../lib/reactivex.das
require daslib/rtti
require strings

var simple_released=0
struct SimpleCapture {
    data:array<int>
    def finalize {if(!empty(data)) {simple_released++;delete data}}
}

def close_from_next(var pipeline:auto;subject:auto;mode,before:int) {
    var sub <- rx_subscription()
    var calls=0
    unsafe {
        rx_subscribe_with(sub,pipeline,@ capture(&pipeline,&sub,&subject,&calls,copy(mode),copy(before)) (n:int) {
            calls++
            delete pipeline
            rx_unsubscribe(sub)
            verify(simple_released==before)
            rx_subject_next(subject,99)
            verify(simple_released==before)
            if(mode==1) {panic("subscriber failed")}
        },@(s:string) {panic(s)},@() {panic("unexpected completion")})
    }
    var caught=false
    try {
        for(n in range(1,4)) {if(rx_is_closed(sub)) {break};rx_subject_next(subject,n)}
    } recover {
        caught=true;verify(starts_with("{this_context().last_exception}","subscriber failed"))
    }
    verify(caught==(mode==1) && calls==1 && rx_is_closed(sub))
    verify(rx_subscriber_count(subject)==0 && simple_released==before+1)
    delete sub;delete pipeline
    verify(simple_released==before+1)
}

def simple_checks() {
    for(mode in range(2)) {
        for(name in fixed_array("scan","distinct","tap","take","skip","take_while","skip_while","pairwise")) {
            let before=simple_released
            var inscope subject <- rx_subject(type<int>)
            var payload <- SimpleCapture(data <- [42])
            var source <- rx_clone(subject) |> rx_tap(@ capture(<-payload) (n:int) {
                verify(payload.data[0]==42)
            } finally {delete payload})
            if(name=="scan") {
                var pipeline <- source |> rx_scan(0,@(acc,n:int) {return acc+n})
                close_from_next(pipeline,subject,mode,before)
            } elif(name=="distinct") {
                var pipeline <- source |> rx_distinct_until_changed()
                close_from_next(pipeline,subject,mode,before)
            } elif(name=="tap") {
                var pipeline <- source |> rx_tap(@(n:int) {})
                close_from_next(pipeline,subject,mode,before)
            } elif(name=="take") {
                var pipeline <- source |> rx_take(2)
                close_from_next(pipeline,subject,mode,before)
            } elif(name=="skip") {
                var pipeline <- source |> rx_skip(1)
                close_from_next(pipeline,subject,mode,before)
            } elif(name=="take_while") {
                var pipeline <- source |> rx_take_while(@(n:int) {return n<4})
                close_from_next(pipeline,subject,mode,before)
            } elif(name=="skip_while") {
                var pipeline <- source |> rx_skip_while(@(n:int) {return n<2})
                close_from_next(pipeline,subject,mode,before)
            } else {
                var pipeline <- source |> rx_pairwise() |> rx_map(@(p:tuple<previous:int;current:int>) {return p.previous+p.current})
                close_from_next(pipeline,subject,mode,before)
            }
            delete source
        }
    }
}

[export]
def main() {
    simple_checks()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {simple_checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX simple operator ownership checks OK\n")
}
