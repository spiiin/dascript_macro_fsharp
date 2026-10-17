options gen2
require ../lib/computation.das

struct Trace {
    source : int
    condition : int
    attempted : int
    completed : int
    after : int
    selected : int
    unselected : int
}
def step(builder : ResultBuilder; var trace : Trace; value, fail_at : int) {
    trace.attempted++
    if (value == fail_at) { return result_error("failed {value}", type<int>) }
    return result_ok(value)
}
def step(builder : OptionBuilder; var trace : Trace; value, fail_at : int) {
    trace.attempted++
    if (value == fail_at) { return none(type<int>) }
    return some(value)
}
def source(var trace : Trace; count : int) : range {
    trace.source++
    return range(count)
}
def condition(var trace : Trace; i, count : int) : bool {
    trace.condition++
    return i < count
}
def check(builder : ResultBuilder; value : variant<ok : int; error : string>; failed : bool; expected : int) {
    if (failed) {
        assert(value is error && (value as error) == "failed {expected}")
    } else { assert(value is ok && (value as ok) == expected) }
}
def check(builder : OptionBuilder; value : variant<some : int; none : bool>; failed : bool; expected : int) {
    if (failed) { assert(value is none) }
    else { assert(value is some && (value as some) == expected) }
}
def test_for(builder : auto; count, fail_at : int) {
    var trace : Trace
    let value = computation(builder) {
        for (i in source(trace, count)) {
            if (i % 2 == 0) {
                trace.selected++
                step(builder, trace, i, fail_at) |> bind
            } else {
                let n = step(builder, trace, i, fail_at) |> bind
                assert(n == i)
            }
            trace.completed++
        }
        trace.after++
        return trace.completed
    }
    let failed = fail_at >= 0 && fail_at < count
    check(builder, value, failed, failed ? fail_at : count)
    assert(trace.source == 1)
    assert(trace.attempted == (failed ? fail_at + 1 : count))
    assert(trace.completed == (failed ? fail_at : count))
    assert(trace.after == (failed ? 0 : 1))
}
def test_while(builder : auto; count, fail_at : int) {
    var trace : Trace
    var i = 0
    let value = computation(builder) {
        while (condition(trace, i, count)) {
            step(builder, trace, i, fail_at) |> bind
            i++
            trace.completed++
        }
        trace.after++
        return i
    }
    let failed = fail_at >= 0 && fail_at < count
    check(builder, value, failed, failed ? fail_at : count)
    assert(trace.condition == (failed ? fail_at + 1 : count + 1))
    assert(trace.attempted == (failed ? fail_at + 1 : count))
    assert(trace.completed == (failed ? fail_at : count))
    assert(trace.after == (failed ? 0 : 1))
}
def test_nested(builder : auto; fail_at : int) {
    var trace : Trace
    let value = computation(builder) {
        for (i in range(2)) {
            var j = 0
            while (j < 3) {
                let n = step(builder, trace, i * 3 + j, fail_at) |> bind
                trace.completed++
                j++
            }
        }
        trace.after++
        return trace.completed
    }
    check(builder, value, fail_at >= 0, fail_at >= 0 ? fail_at : 6)
    assert(trace.attempted == (fail_at >= 0 ? fail_at + 1 : 6))
    assert(trace.completed == (fail_at >= 0 ? fail_at : 6))
    assert(trace.after == (fail_at >= 0 ? 0 : 1))
}
def test_branches(builder : auto; flag : int; fail_at : int) {
    var trace : Trace
    let value = computation(builder) {
        if (flag == 0) {
            trace.selected++
            step(builder, trace, 0, fail_at) |> bind
        } elif (flag == 1) {
            trace.selected++
            step(builder, trace, 0, fail_at) |> bind
        } else {
            trace.selected++
            step(builder, trace, 0, fail_at) |> bind
        }
        if (false) { trace.unselected++ }
        trace.after++
        if (flag == 0) {
            let x = step(builder, trace, 1, -1) |> bind
            return x + 9
        } elif (flag == 1) { return 10 }
        else { return 10 }
    }
    check(builder, value, fail_at == 0, fail_at == 0 ? 0 : 10)
    assert(trace.selected == 1 && trace.unselected == 0)
    assert(trace.attempted == (fail_at == 0 || flag != 0 ? 1 : 2))
    assert(trace.after == (fail_at == 0 ? 0 : 1))
}
def test_skipped_sources(builder : auto) {
    var trace : Trace
    let value = computation(builder) {
        step(builder, trace, 0, 0) |> bind
        for (i in source(trace, 3)) { trace.completed++ }
        while (condition(trace, 0, 1)) { trace.completed++ }
        trace.after++
        return 42
    }
    check(builder, value, true, 0)
    assert(trace.attempted == 1 && trace.source == 0 && trace.condition == 0)
    assert(trace.completed == 0 && trace.after == 0)

    // A failing guard skips sources in the next combined computation too.
    let guarded = computation(builder) {
        if (true) { step(builder, trace, 1, 1) |> bind }
        for (i in source(trace, 3)) { trace.completed++ }
        return 42
    }
    check(builder, guarded, true, 1)
    assert(trace.attempted == 2 && trace.source == 0 && trace.completed == 0)

    // A terminal while returns Unit or propagates failure without a final return.
    var i = 0
    let terminal = computation(builder) {
        while (i < 3) {
            step(builder, trace, i, 1) |> bind
            i++
        }
    }
    assert(ce_loop_failed(builder, terminal) && i == 1)
}
def test_all(builder : auto) {
    test_skipped_sources(builder)
    test_for(builder, 10000, -1)
    test_while(builder, 10000, -1)
    for (count in range(5)) {
        for (fail_at in range(-1, count + 1)) {
            test_for(builder, count, fail_at)
            test_while(builder, count, fail_at)
        }
    }
    for (fail_at in range(-1, 6)) { test_nested(builder, fail_at) }
    for (flag in range(3)) {
        test_branches(builder, flag, -1)
        test_branches(builder, flag, 0)
    }
    var trace : Trace
    let empty_value = computation(builder) {}
    assert(!ce_loop_failed(builder, empty_value))
    let no_return = computation(builder) {
        step(builder, trace, 0, -1) |> bind
    }
    assert(!ce_loop_failed(builder, no_return) && trace.attempted == 1)
    let empty_branch = computation(builder) { if (false) { trace.unselected++ } }
    assert(!ce_loop_failed(builder, empty_branch) && trace.unselected == 0)
    let terminal_loop = computation(builder) {
        for (i in range(3)) { step(builder, trace, i, -1) |> bind }
    }
    assert(!ce_loop_failed(builder, terminal_loop) && trace.attempted == 4)
    var forced = 0
    let delayed = ce_delay(builder, $ { forced++; return ce_zero(builder) })
    assert(forced == 1 && !ce_loop_failed(builder, delayed))
}
[export]
def main() {
    test_all(ResultBuilder())
    test_all(OptionBuilder())
    print("control flow checks OK: Result/Option, branches, empty scopes, for/while, nested loops, exact effects\n")
}

