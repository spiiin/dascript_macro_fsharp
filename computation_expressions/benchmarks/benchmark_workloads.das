options gen2
module benchmark_workloads public
require ../lib/computation.das public

def private checked(value:int) {
    if (value%7==0) {return result_error("invalid",type<int>)}
    return result_ok(value+1)
}
def bench_result_ce(seed:int) : int64 {
    let builder=ResultBuilder()
    let result=computation(builder) {
        let a=checked(seed) |> bind
        let b=checked(a*2) |> bind
        let c=checked(b+3) |> bind
        return c*2
    }
    return result is error ? -1l : int64(result as ok)
}
def bench_result_manual(seed:int) : int64 {
    let a=checked(seed)
    if (a is error) {return -1l}
    let b=checked((a as ok)*2)
    if (b is error) {return -1l}
    let c=checked((b as ok)+3)
    if (c is error) {return -1l}
    return int64((c as ok)*2)
}
def bench_state_ce(seed:int) : int64 {
    let builder=StateBuilder(seed)
    let result=computation(builder) {
        for (i in range(16)) {
            let state=state_get() |> bind
            state_put(state+i) |> bind
        }
        let state=state_get() |> bind
        return state*2
    }
    return int64(result.value)+int64(result.state)
}
def bench_state_manual(seed:int) : int64 {
    var state=seed
    for (i in range(16)) {state+=i}
    let result=state_result(state*2,state)
    return int64(result.value)+int64(result.state)
}
def private list_checksum(values:array<int>) : int64 {
    var checksum=0l
    for (i in range(length(values))) {checksum+=int64(i+1)*int64(values[i])}
    return checksum
}
def bench_list_ce(seed:int) : int64 {
    let builder=ListBuilder()
    var inscope values <- computation(builder) {
        let x=fixed_array(seed,seed+1,seed+2,seed+3) |> bind
        let y=fixed_array(1,2,3,4) |> bind
        return x*y
    }
    return list_checksum(values)
}
def bench_list_manual(seed:int) : int64 {
    var inscope values:array<int>
    for (x in fixed_array(seed,seed+1,seed+2,seed+3)) {
        for (y in fixed_array(1,2,3,4)) {values |> push(x*y)}
    }
    return list_checksum(values)
}
def private sequence_checksum(var source:iterator<int>) : int64 {
    var checksum=0l
    var index=1l
    sequence_each(source,$(value:int) {checksum+=index*int64(value); index++})
    return checksum
}
def bench_sequence_ce(seed:int) : int64 {
    let builder=SequenceBuilder()
    var inscope source <- computation(builder) {
        for (i in range(32)) {yield seed+i*2}
    }
    return sequence_checksum(source)
}
def bench_sequence_manual(seed:int) : int64 {
    var native <- generator<int> {
        for (i in range(32)) {yield seed+i*2}
        return false
    }
    // Same protection and consumption contract as the CE iterator.
    var inscope source <- ce_sequence_protect(native)
    return sequence_checksum(source)
}

// Nonlinear, runtime-sized work: seed changes both length and state.
def state_variable_ce(seed, steps:int) : int64 {
    let result=computation(StateBuilder(seed)) {
        for (i in range(steps)) {
            let current=state_get() |> bind
            state_put((current*33+i)%1000003) |> bind
        }
        let current=state_get() |> bind
        return current*2
    }
    return int64(result.value)+int64(result.state)
}
def state_variable_manual(seed, steps:int) : int64 {
    var state=seed
    for (i in range(steps)) {state=(state*33+i)%1000003}
    let result=state_result(state*2,state)
    return int64(result.value)+int64(result.state)
}
def bench_state_variable_ce(seed:int) : int64 {return state_variable_ce(seed,(seed*13)%97)}
def bench_state_variable_manual(seed:int) : int64 {return state_variable_manual(seed,(seed*13)%97)}

def state_variable_while_ce(seed, steps:int) : int64 {
    let result=computation(StateBuilder(seed)) {
        var i=0
        while (i<steps) {
            let current=state_get() |> bind
            state_put((current*33+i)%1000003) |> bind
            i++
        }
        let current=state_get() |> bind
        return current*2
    }
    return int64(result.value)+int64(result.state)
}
def bench_state_variable_while_ce(seed:int) : int64 {return state_variable_while_ce(seed,(seed*13)%97)}
