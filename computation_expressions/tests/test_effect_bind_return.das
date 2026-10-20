options gen2
require ../lib/computation.das

var maps=0
var closes=0
struct Resource {}
def ce_dispose(var resource:Resource) { closes++ }
def mapped(value:int) { maps++; return (payload=value+1) }
def fail_map(value:int) : int { panic("mapper failure"); return value }
[export]
def main() {
    let stateGetFast=computation(StateBuilder(10)) { let x=state_get() |> bind; return mapped(x) }
    let stateGetSlow=computation(StateBuilder(10)) { let x=state_get() |> bind; let unused=0; return mapped(x) }
    assert((typeinfo typename(stateGetFast))==(typeinfo typename(stateGetSlow)))
    assert("{stateGetFast}"=="{stateGetSlow}")
    let statePutFast=computation(StateBuilder(10)) { let x=state_put(20) |> bind; return mapped(1) }
    let statePutSlow=computation(StateBuilder(10)) { let x=state_put(20) |> bind; let unused=0; return mapped(1) }
    assert((typeinfo typename(statePutFast))==(typeinfo typename(statePutSlow)))
    assert("{statePutFast}"=="{statePutSlow}")
    let stateValueFast=computation(StateBuilder(10)) { let x=state_result(2,30) |> bind; return mapped(x) }
    let stateValueSlow=computation(StateBuilder(10)) { let x=state_result(2,30) |> bind; let unused=0; return mapped(x) }
    assert((typeinfo typename(stateValueFast))==(typeinfo typename(stateValueSlow)))
    assert("{stateValueFast}"=="{stateValueSlow}")
    let srGetFast=computation(StateResultBuilder(10)) { let x=state_get() |> bind; return mapped(x) }
    let srGetSlow=computation(StateResultBuilder(10)) { let x=state_get() |> bind; let unused=0; return mapped(x) }
    assert((typeinfo typename(srGetFast))==(typeinfo typename(srGetSlow)))
    assert("{srGetFast}"=="{srGetSlow}")
    let srPutFast=computation(StateResultBuilder(10)) { let x=state_put(20) |> bind; return mapped(1) }
    let srPutSlow=computation(StateResultBuilder(10)) { let x=state_put(20) |> bind; let unused=0; return mapped(1) }
    assert((typeinfo typename(srPutFast))==(typeinfo typename(srPutSlow)))
    assert("{srPutFast}"=="{srPutSlow}")
    let srResultFast=computation(StateResultBuilder(10)) { let x=result_ok(2) |> bind; return mapped(x) }
    let srResultSlow=computation(StateResultBuilder(10)) { let x=result_ok(2) |> bind; let unused=0; return mapped(x) }
    assert((typeinfo typename(srResultFast))==(typeinfo typename(srResultSlow)))
    assert("{srResultFast}"=="{srResultSlow}")
    let srValueFast=computation(StateResultBuilder(10)) { let x=state_result_ok(2,30) |> bind; return mapped(x) }
    let srValueSlow=computation(StateResultBuilder(10)) { let x=state_result_ok(2,30) |> bind; let unused=0; return mapped(x) }
    assert((typeinfo typename(srValueFast))==(typeinfo typename(srValueSlow)))
    assert("{srValueFast}"=="{srValueSlow}")
    let wrValueFast=computation(WriterResultBuilder()) { let x=writer_result_ok(2,"log;") |> bind; return mapped(x) }
    let wrValueSlow=computation(WriterResultBuilder()) { let x=writer_result_ok(2,"log;") |> bind; let unused=0; return mapped(x) }
    assert((typeinfo typename(wrValueFast))==(typeinfo typename(wrValueSlow)))
    assert("{wrValueFast}"=="{wrValueSlow}")
    let wrResultFast=computation(WriterResultBuilder()) { let x=result_ok(2) |> bind; return mapped(x) }
    let wrResultSlow=computation(WriterResultBuilder()) { let x=result_ok(2) |> bind; let unused=0; return mapped(x) }
    assert((typeinfo typename(wrResultFast))==(typeinfo typename(wrResultSlow)))
    assert("{wrResultFast}"=="{wrResultSlow}")
    let wrTellFast=computation(WriterResultBuilder()) { let x=tell("log;") |> bind; return mapped(1) }
    let wrTellSlow=computation(WriterResultBuilder()) { let x=tell("log;") |> bind; let unused=0; return mapped(1) }
    assert((typeinfo typename(wrTellFast))==(typeinfo typename(wrTellSlow)))
    assert("{wrTellFast}"=="{wrTellSlow}")
    static_assert((typeinfo ce_has_bind_return(ce_bind_return(StateBuilder(10), state_get(), $(x:typedecl(ce_unwrap(StateBuilder(10), state_get()))) { return 1 }))), "expected specialized BindReturn")
    static_assert((typeinfo ce_has_bind_return(ce_bind_return(StateBuilder(10), state_put(20), $(x:typedecl(ce_unwrap(StateBuilder(10), state_put(20)))) { return 1 }))), "expected specialized BindReturn")
    static_assert((typeinfo ce_has_bind_return(ce_bind_return(StateBuilder(10), state_result(2,30), $(x:typedecl(ce_unwrap(StateBuilder(10), state_result(2,30)))) { return 1 }))), "expected specialized BindReturn")
    static_assert((typeinfo ce_has_bind_return(ce_bind_return(StateResultBuilder(10), state_get(), $(x:typedecl(ce_unwrap(StateResultBuilder(10), state_get()))) { return 1 }))), "expected specialized BindReturn")
    static_assert((typeinfo ce_has_bind_return(ce_bind_return(StateResultBuilder(10), state_put(20), $(x:typedecl(ce_unwrap(StateResultBuilder(10), state_put(20)))) { return 1 }))), "expected specialized BindReturn")
    static_assert((typeinfo ce_has_bind_return(ce_bind_return(StateResultBuilder(10), result_ok(2), $(x:typedecl(ce_unwrap(StateResultBuilder(10), result_ok(2)))) { return 1 }))), "expected specialized BindReturn")
    static_assert((typeinfo ce_has_bind_return(ce_bind_return(StateResultBuilder(10), state_result_ok(2,30), $(x:typedecl(ce_unwrap(StateResultBuilder(10), state_result_ok(2,30)))) { return 1 }))), "expected specialized BindReturn")
    static_assert((typeinfo ce_has_bind_return(ce_bind_return(WriterResultBuilder(), writer_result_ok(2,"log;"), $(x:typedecl(ce_unwrap(WriterResultBuilder(), writer_result_ok(2,"log;")))) { return 1 }))), "expected specialized BindReturn")
    static_assert((typeinfo ce_has_bind_return(ce_bind_return(WriterResultBuilder(), result_ok(2), $(x:typedecl(ce_unwrap(WriterResultBuilder(), result_ok(2)))) { return 1 }))), "expected specialized BindReturn")
    static_assert((typeinfo ce_has_bind_return(ce_bind_return(WriterResultBuilder(), tell("log;"), $(x:typedecl(ce_unwrap(WriterResultBuilder(), tell("log;")))) { return 1 }))), "expected specialized BindReturn")
    assert(maps==20)
    let rollback=computation(StateResultBuilder(10)) {
        state_put(99) |> bind
        let n=result_error("stop",type<int>) |> bind
        return mapped(n)
    }
    assert(rollback.result is err && rollback.state==10 && maps==20)
    let foreignError=computation(StateResultBuilder(10)) {
        state_put(99) |> bind
        let n=state_result_error("foreign",type<int>,777) |> bind
        return mapped(n)
    }
    assert(foreignError.result is err && foreignError.state==10 && maps==20)
    let loggedError=computation(WriterResultBuilder()) {
        tell("before;") |> bind
        let n=writer_result_error("stop",type<int>,"failure;") |> bind
        return mapped(n)
    }
    assert(loggedError.result is err && loggedError.log=="before;failure;" && maps==20)
    let bareError=computation(WriterResultBuilder()) {
        tell("before;") |> bind
        let n=result_error("stop",type<int>) |> bind
        return mapped(n)
    }
    assert(bareError.result is err && bareError.log=="before;" && maps==20)
    var state=StateBuilder(10)
    let snapshot=ce_bind_return(state,state_get(),$(n:int) { state.state=20; return n+1 })
    assert(snapshot.value==11 && snapshot.state==20 && state.state==20)
    var transaction=StateResultBuilder(10)
    let transactionalSnapshot=ce_bind_return(transaction,state_get(),$(n:int) { transaction.state=20; return n+1 })
    assert(transactionalSnapshot.result is ok && (transactionalSnapshot.result as ok)==11 && transactionalSnapshot.state==20)
    var caught=false
    try {
        let unused=ce_bind_return(transaction,state_put(50),$(unit:CeUnit) { return fail_map(1) })
    } recover { caught=true }
    assert(caught && transaction.state==50)
    let reset=ce_bind_return(transaction,result_error("reset",type<int>),$(n:int) { return mapped(n) })
    assert(reset.result is err && transaction.state==10 && reset.state==10 && maps==20)
    caught=false
    try {
        let unused=computation(StateResultBuilder(10)) {
            let resource=Resource() |> use_resource
            let n=result_ok(1) |> bind
            return fail_map(n)
        }
    } recover { caught=true }
    assert(caught && closes==1)
    caught=false
    try {
        let unused=computation(WriterResultBuilder()) {
            let resource=Resource() |> use_resource
            let n=writer_result_ok(1,"before;") |> bind
            return fail_map(n)
        }
    } recover { caught=true }
    assert(caught && closes==2)
    print("effect bind_return checks OK\n")
}

