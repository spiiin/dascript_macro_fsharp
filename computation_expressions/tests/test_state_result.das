options gen2
require ../support/game_transaction.das
struct Trace { attempted : int; after : int; condition : int; source : int; builder : int }
def checked_step(var trace : Trace; index, fail_at : int) {
    trace.attempted++
    if (index == fail_at) { return result_error("failure {index}", type<int>) }
    return result_ok(index)
}
def counted_builder(var trace : Trace) { trace.builder++; return StateResultBuilder(10) }
def source(var trace : Trace; count : int) : range { trace.source++; return range(count) }
def condition(var trace : Trace; index, count : int) : bool { trace.condition++; return index < count }
def test_linear(fail_at : int) {
    var trace : Trace
    let result = computation(counted_builder(trace)) {
        state_put(20) |> bind
        let a = checked_step(trace, 0, fail_at) |> bind
        state_put(30) |> bind
        let b = checked_step(trace, 1, fail_at) |> bind
        state_put(40) |> bind
        checked_step(trace, 2, fail_at) |> bind
        trace.after++
        return "sum={a+b}"
    }
    assert(trace.builder == 1 && trace.attempted == (fail_at < 0 ? 3 : fail_at + 1))
    assert(trace.after == (fail_at < 0 ? 1 : 0))
    if (fail_at < 0) {
        assert(result.result is ok && (result.result as ok) == "sum=1" && result.state == 40)
    } else {
        assert(result.result is err && (result.result as err) == "failure {fail_at}" && result.state == 10)
    }
}
def test_loops(count, fail_at : int; use_while : bool) {
    var trace : Trace
    let output = computation(StateResultBuilder(10)) {
        state_put(100) |> bind
        if (use_while) {
            var i = 0
            while (condition(trace, i, count)) {
                let n = state_get() |> bind
                state_put(n + 1) |> bind
                checked_step(trace, i, fail_at) |> bind
                i++
            }
        } else {
            for (i in source(trace, count)) {
                let n = state_get() |> bind
                state_put(n + 1) |> bind
                if (i % 2 == 0) { checked_step(trace, i, fail_at) |> bind }
                else { let x = checked_step(trace, i, fail_at) |> bind }
            }
        }
        trace.after++
        let final_state = state_get() |> bind
        return final_state
    }
    let failed = fail_at >= 0 && fail_at < count
    assert(trace.attempted == (failed ? fail_at + 1 : count))
    assert(trace.after == (failed ? 0 : 1))
    assert(trace.source == (use_while ? 0 : 1))
    assert(trace.condition == (use_while ? (failed ? fail_at + 1 : count + 1) : 0))
    if (failed) {
        assert(output.result is err && (output.result as err) == "failure {fail_at}" && output.state == 10)
    } else {
        assert(output.result is ok && (output.result as ok) == 100 + count && output.state == 100 + count)
    }
}
def test_nested_loops(fail_at : int) {
    var trace : Trace
    let output = computation(StateResultBuilder(10)) {
        state_put(100) |> bind
        for (i in range(2)) {
            var j = 0
            while (j < 2) {
                let state = state_get() |> bind
                state_put(state + 1) |> bind
                checked_step(trace, i * 2 + j, fail_at) |> bind
                j++
            }
        }
    }
    assert(trace.attempted == (fail_at < 0 ? 4 : fail_at + 1))
    assert(output.state == (fail_at < 0 ? 104 : 10))
    assert((output.result is err) == (fail_at >= 0))
}
def child(initial : int; fail : bool) {
    return computation(StateResultBuilder(initial)) {
        state_put(initial + 5) |> bind
        if (fail) { return result_error("child failed", type<string>) |> return_from }
        else { return "child committed" }
    }
}
def test_composition() {
    let failed_child = child(50, true)
    assert(failed_child.result is err && failed_child.state == 50)
    var after = 0
    let failed_parent = computation(StateResultBuilder(10)) {
        state_put(50) |> bind
        let current = state_get() |> bind
        child(current, true) |> bind
        after++
        return 42
    }
    assert(failed_parent.result is err && (failed_parent.result as err) == "child failed")
    assert(failed_parent.state == 10 && after == 0)
    let success = computation(StateResultBuilder(10)) {
        state_put(50) |> bind
        let message = child(50, false) |> bind
        let current = state_get() |> bind
        assert(current == 55)
        return message
    }
    assert(success.result is ok && success.state == 55)
    let failed_after_commit = computation(StateResultBuilder(10)) {
        child(50, false) |> bind
        let current = state_get() |> bind
        assert(current == 55)
        return result_error("later failure", type<int>) |> return_from
    }
    assert(failed_after_commit.result is err && failed_after_commit.state == 10)
    let ignored_child = computation(StateResultBuilder(10)) {
        state_put(20) |> bind
        let ignored = child(90, true)
        return 1
    }
    assert(ignored_child.result is ok && ignored_child.state == 20)
    let forwarded_child = computation(StateResultBuilder(10)) {
        state_put(20) |> bind
        return child(50, true) |> return_from
    }
    assert(forwarded_child.result is err && forwarded_child.state == 10)
    let forged_failure = computation(StateResultBuilder(10)) {
        return state_result_error("ignore foreign state", type<int>, 999) |> return_from
    }
    assert(forged_failure.result is err && forged_failure.state == 10)
    let forwarded_ok = computation(StateResultBuilder(10)) {
        return state_result_ok("ok", 30) |> return_from
    }
    assert(forwarded_ok.result is ok && forwarded_ok.state == 30)
}
def test_edges() {
    let empty_value = computation(StateResultBuilder(10)) {}
    assert(empty_value.result is ok && empty_value.state == 10)
    let no_return = computation(StateResultBuilder(10)) { state_put(20) |> bind }
    assert(no_return.result is ok && no_return.state == 20)
    let snapshot = computation(StateResultBuilder(10)) {
        let before = state_get() |> bind
        let unused_put = state_put(999)
        state_put(20) |> bind
        let current = state_get() |> bind
        assert(before == 10 && current == 20)
        return current
    }
    assert(snapshot.result is ok && snapshot.state == 20)
    var trace : Trace
    let skipped = computation(StateResultBuilder(10)) {
        state_put(20) |> bind
        if (true) { checked_step(trace, 0, 0) |> bind }
        for (i in source(trace, 3)) { state_put(i) |> bind }
        while (condition(trace, 0, 1)) { state_put(100) |> bind }
        return 1
    }
    assert(skipped.result is err && skipped.state == 10)
    assert(trace.attempted == 1 && trace.source == 0 && trace.condition == 0)
    let terminal_while = computation(StateResultBuilder(10)) {
        state_put(20) |> bind
        while (true) {
            state_put(30) |> bind
            result_error("stop", type<int>) |> bind
        }
    }
    assert(terminal_while.result is err && terminal_while.state == 10)
    // A Result returned without return_from is ordinary data, not failure.
    let payload = computation(StateResultBuilder(10)) {
        state_put(20) |> bind
        return result_error("payload", type<int>)
    }
    assert(payload.result is ok && ((payload.result as ok) is err) && payload.state == 20)
    let initial = AdventureState(health=50, gold=30, potions=2, turns=0)
    var reached = 0
    let first = adventure_turn(initial, 100, reached)
    let second = adventure_turn(initial, 10, reached)
    assert(first.state.health == 50 && second.state.health == 60 && initial.health == 50)
}
[export]
def main() {
    for (fail_at in range(-1, 3)) { test_linear(fail_at) }
    for (count in range(5)) {
        for (fail_at in range(-1, count + 1)) {
            test_loops(count, fail_at, false)
            test_loops(count, fail_at, true)
        }
    }
    for (fail_at in range(-1, 4)) { test_nested_loops(fail_at) }
    test_loops(10000, -1, false)
    test_composition()
    test_edges()
    print("state/result checks OK: whole-transaction rollback, nested boundaries, exact effects, loops, snapshots\n")
}
