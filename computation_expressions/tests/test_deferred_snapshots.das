options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
struct Config {
    name:string
    amounts:array<int>
}
struct Game { gold:int }
var cloned=0
var rejectClone=false
struct Fragile { amounts:array<int> }
def clone(var dest:Fragile; src:Fragile) {
    cloned++
    dest.amounts := src.amounts
    if (rejectClone) { panic("clone failed") }
}
[export]
def main() {
    let baseline=heap_bytes_allocated()
    for (i in range(10)) {
        {
            var inscope config:Config
            config.name="reward"
            config.amounts <- [2,4]
            var inscope task <- deferred(StateBuilder(Game(gold=10)),config) $(snapshot) {
                var game=state_get() |> bind
                game.gold+=snapshot.amounts[0]+snapshot.amounts[1]
                state_put(game) |> bind
                snapshot.amounts[0]=999
                return snapshot.name
            }
            config.amounts[0]=500
            delete config
            let a=run_deferred(task)
            let b=run_deferred(task)
            assert(a.value=="reward" && a.state.gold==16 && b.state.gold==16)
        }
        {
            var inscope value:Fragile
            value.amounts <- [1,2,3]
            var inscope task <- deferred(ResultBuilder(),value) $(snapshot) { return length(snapshot.amounts) }
            rejectClone=true
            var caught=false
            try { let ignored=run_deferred(task) } recover { caught=true }
            assert(caught)
            rejectClone=false
            let after=run_deferred(task)
            assert(after as ok==3)
            rejectClone=true
            caught=false
            try { var inscope ignored <- deferred(ResultBuilder(),value) $(snapshot) { return length(snapshot.amounts) } } recover { caught=true }
            assert(caught)
            rejectClone=false
        }
        let after=heap_bytes_allocated()
        assert(after==baseline)
    }
    assert(cloned==40)
    print("deferred snapshot checks OK\n")
}
