options gen2
require ../../lib/computation.das

def work(seed:int) : int64 {
    let result=computation(StateBuilder(seed)) {
        for(i in range(16)){let n=state_get() |> bind;state_put(n+i) |> bind}
        let n=state_get() |> bind
        return n*2
    }
    return int64(result.value)+int64(result.state)
}
[export]
def main() {
    var checksum=0l
    for(seed in range(64)){checksum+=work(seed)}
    print("CHECKSUM,{checksum}\n")
}