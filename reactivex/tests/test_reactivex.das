options gen2
options max_infer_passes=256
require ../lib/reactivex.das
require daslib/rtti
var total=0
var done=0
var destroyed=0
var itemFinalized=0
struct CopyItem {value:int
    def finalize {itemFinalized++}
}
def next_handler() {return <- @(n:int) {} finally {destroyed++}}
def error_handler() {return <- @(message:string) {} finally {destroyed++}}
def done_handler() {return <- @() {} finally {destroyed++}}
def checks() {
    let initial=total
    let completed=done
    {
        var inscope source <- rx_range(1,3)
        var inscope sub <- rx_subscribe(source,@(n:int) {total+=n},@(message:string) {panic(message)},@(){done++})
        verify(total==initial+6 && done==completed+1 && rx_is_closed(sub))
        verify(!rx_unsubscribe(sub))
    }
    {
        var inscope source <- rx_range(2147483647,1)
        var inscope sub <- rx_subscribe(source,@(n:int) {verify(n==2147483647)},@(message:string) {panic(message)},@(){done++})
        var inscope emptySource <- rx_range(0,0)
        var inscope emptySub <- rx_subscribe(emptySource,@(n:int) {panic("empty emitted")},@(message:string) {panic(message)},@(){done++})
        verify(done==completed+3)
    }
    for(mode in range(2)) {
        var caught=false
        try {var source <- rx_range(mode==0 ? 0 : 2147483647,mode==0 ? -1 : 2);delete source} recover {caught=true}
        verify(caught)
    }
    {
        let finalized=itemFinalized
        var inscope subject <- rx_subject(type<CopyItem>)
        verify(itemFinalized==finalized) // type markers must not construct T
    }
    {
        var inscope source <- rx_range(0,10)
        var inscope sub <- rx_subscription()
        verify(rx_unsubscribe(sub))
        let released=destroyed
        rx_subscribe_with(sub,source,next_handler(),error_handler(),done_handler())
        verify(destroyed==released+3)
        var caught=false
        try {rx_subscribe_with(sub,source,next_handler(),error_handler(),done_handler())} recover {caught=true}
        verify(caught && destroyed==released+6)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(20)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX core checks OK\n")
}
