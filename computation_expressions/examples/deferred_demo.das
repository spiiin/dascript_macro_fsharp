options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
var steps=0
def make_reward() {
    var inscope rewards <- [10,20,30]
    return <- deferred(ResultBuilder(),rewards) $(snapshot) {
        steps++
        let base=result_ok(snapshot[0]+snapshot[1]+snapshot[2]) |> bind
        snapshot[0]=999
        return base+5
    }
}
[export]
def main() {
    var inscope task <- make_reward()
    assert(steps==0)
    let a=run_deferred(task)
    let b=task |> run_deferred
    assert(a is ok && a as ok==65 && b as ok==65 && steps==2)
    print("deferred demo OK\n")
}
