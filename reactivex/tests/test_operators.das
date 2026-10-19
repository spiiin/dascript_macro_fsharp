options gen2
options max_infer_passes=512
require ../lib/reactivex.das
require daslib/rtti
var total=0
var done=0
var effects=0
var tested=0
var factories=0
var errors=0
var text=""

def checks() {
    let oldTotal=total
    let oldDone=done
    let oldEffects=effects
    let oldTested=tested
    {
        var inscope source <- rx_range(1,10) |> rx_filter(@(n:int) {tested++;return n%2==0}) |> rx_map(@(n:int) {effects++;return n*10}) |> rx_take(2)
        for(i in range(2)) {
            var inscope sub <- rx_subscribe(source,@(n:int) {total+=n},@(message:string) {panic(message)},@(){done++})
            verify(rx_is_closed(sub))
        }
    }
    verify(total==oldTotal+120 && done==oldDone+2 && effects==oldEffects+4 && tested==oldTested+8)
    {
        let first=factories
        var inscope deferred <- rx_defer(@() {factories++;return <- rx_range(factories,1)})
        for(i in range(2)) {var inscope sub <- rx_subscribe(deferred,@(n:int) {},@(message:string) {panic(message)},@(){done++})}
        verify(factories==first+2)
        var inscope zero <- rx_clone(deferred) |> rx_take(0)
        var inscope sub <- rx_subscribe(zero,@(n:int) {panic("take(0) emitted")},@(message:string) {panic(message)},@(){done++})
        verify(factories==first+2 && rx_is_closed(sub))
    }
    // Array source owns a snapshot; map can change the element type.
    {
        var inscope items:array<int>
        items <- [3,4]
        var inscope source <- rx_from_array(items) |> rx_map(@(n:int) {return "n={n};"})
        items[0]=99
        text=""
        var inscope sub <- rx_subscribe(source,@(value:string) {text+=value},@(message:string) {panic(message)},@(){})
        verify(text=="n=3;n=4;")
    }
    for(mode in range(2)) {
        let oldErrors=errors
        let beforeErrorEffects=effects
        let completed=done
        var inscope source <- rx_range(1,10) |> rx_map(@ capture(copy(mode)) (n:int) {
            effects++
            if(mode==0 && n==2) {panic("map failed")}
            return n
        }) |> rx_filter(@ capture(copy(mode)) (n:int) {
            if(mode==1 && n==2) {panic("filter failed")}
            return true
        })
        var inscope sub <- rx_subscribe(source,@(n:int) {},@(message:string) {errors++},@(){done++})
        verify(errors==oldErrors+1 && effects==beforeErrorEffects+2 && done==completed && rx_is_closed(sub))
    }
    {
        let oldErrors=errors
        var inscope source <- rx_defer(@() {panic("factory failed");return <- rx_range(1,1)})
        var inscope sub <- rx_subscribe(source,@(n:int) {},@(message:string) {errors++},@(){panic("unexpected completion")})
        verify(errors==oldErrors+1 && rx_is_closed(sub))
    }
    // Repeated type-changing operators must not inherit stale T/U aliases
    // from nested source descriptors (int -> string -> int -> string).
    {
        text=""
        var inscope source <- rx_range(1,5) |> rx_map(@(n:int) {return "v={n}"}) |> rx_take(3) |> rx_map(@(value:string) {return length(value)}) |> rx_filter(@(n:int) {return n==3}) |> rx_take(2) |> rx_map(@(n:int) {return "{n};"})
        var inscope sub <- rx_subscribe(source,@(value:string) {text+=value},@(message:string) {panic(message)},@(){})
        verify(text=="3;3;")
    }
    // Observer errors propagate out of cold chains too, after owned frames close.
    {
        var inscope source <- rx_defer(@() {return <- rx_range(1,3) |> rx_map(@(n:int) {return n})}) |> rx_take(2)
        var caught=false
        try {
            var sub <- rx_subscribe(source,@(n:int) {panic("observer failed")},@(message:string) {panic("must not become on_error")},@(){})
            delete sub
        } recover {caught=true}
        verify(caught)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(20)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX operator checks OK\n")
}
