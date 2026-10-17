options gen2
require ../../lib/computation.das
var cleaned=0
[export]
def main() {
    let r=computation(StateBuilder(0)) {
        try_with($ {
            try_finally($ {
                state_put(12) |> bind
                panic("expected")
                return 0
            }, $ {cleaned++})
        }, $(message:string) {
            let n=state_get() |> bind
            return n
        })
    }
    assert(r.value==12 && r.state==12 && cleaned==1)
    print("state panic OK\n")
}
