options gen2
require ../lib/computation.das
require ../lib/state_writer_result_builder.das
require ../lib/deferred_computation.das
require daslib/rtti
var calls=0
[export]
def main() {
    // A failed transformation must not install partially computed state.
    let recovered=computation(StateBuilder(10)) {
        try_with($ {
            state_modify($(n:int) {calls++;panic("modify failed");return n+1}) |> bind
            return 0
        }, $(message:string) {
            let n=state_gets($(value:int) {return value}) |> bind
            return n
        })
    }
    assert(recovered.value==10 && recovered.state==10 && calls==1)
    let rejected=computation(StateResultBuilder(5)) {
        result_error("stop",type<CeUnit>) |> bind
        state_modify($(n:int){calls++;return n+1}) |> bind
        let n=state_gets($(value:int){calls++;return value}) |> bind
        return n
    }
    assert(rejected.result is error && rejected.state==5 && calls==1)
    let projected=computation(StateWriterResultBuilder(7)) {
        tell("before;") |> bind
        try_with($ {
            let n=state_gets($(value:int){calls++;panic("projection failed");return value}) |> bind
            return n
        },$(message:string) {
            return result_error("projection failed",type<int>) |> return_from
        })
    }
    assert(projected.result is error && projected.state==7 && projected.log=="before;" && calls==2)
    // Snapshots are recreated after a failed run; external effects are retained.
    var inscope task <- deferred(StateBuilder(3)) {
        state_modify($(n:int){calls++;if(calls==3){panic("first run")};return n+2}) |> bind
        let n=state_gets($(value:int){return value}) |> bind
        return n
    }
    var failed=false
    try {let ignored=run_deferred(task)} recover {failed=true}
    assert(failed)
    let retried=run_deferred(task)
    assert(retried.value==5 && retried.state==5 && calls==4)
    print("State operation failure checks OK\n")
}
