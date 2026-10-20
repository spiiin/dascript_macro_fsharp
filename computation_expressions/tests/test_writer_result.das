options gen2
require ../support/purchase_example.das
struct Trace { calls : int; completed : int; after : int; condition : int; source : int; builder : int }
def step(var trace : Trace; index, fail_at : int) {
    trace.calls++
    if (index == fail_at) { return writer_result_error("failure {index}", type<int>, "try{index};FAIL;") }
    return writer_result_ok(index, "try{index};")
}
def counted_builder(var trace : Trace) {
    trace.builder++
    return WriterResultBuilder()
}
def loop_source(var trace : Trace; count : int) : range { trace.source++; return range(count) }
def loop_condition(var trace : Trace; index, count : int) : bool { trace.condition++; return index < count }
def test_linear(fail_at : int) {
    var trace : Trace
    let output = computation(counted_builder(trace)) {
        tell("begin;") |> bind
        let a = step(trace, 0, fail_at) |> bind
        let b = step(trace, 1, fail_at) |> bind
        step(trace, 2, fail_at) |> bind
        trace.after++
        return "sum={a+b}"
    }
    assert(trace.builder == 1 && trace.calls == (fail_at < 0 ? 3 : fail_at + 1))
    assert(trace.after == (fail_at < 0 ? 1 : 0))
    var expected = "begin;"
    for (i in range(fail_at < 0 ? 3 : fail_at + 1)) { expected += "try{i};" }
    if (fail_at >= 0) {
        expected += "FAIL;"
        assert(output.result is err && (output.result as err) == "failure {fail_at}")
    } else { assert(output.result is ok && (output.result as ok) == "sum=1") }
    assert(output.log == expected)
}
def test_loops(count, fail_at : int; use_while : bool) {
    var trace : Trace
    let output = computation(WriterResultBuilder()) {
        tell("begin;") |> bind
        if (use_while) {
            var i = 0
            while (loop_condition(trace, i, count)) {
                step(trace, i, fail_at) |> bind
                trace.completed++
                tell("done{i};") |> bind
                i++
            }
        } else {
            for (i in loop_source(trace, count)) {
                if (i % 2 == 0) { step(trace, i, fail_at) |> bind }
                else {
                    let n = step(trace, i, fail_at) |> bind
                    assert(n == i)
                }
                trace.completed++
                tell("done{i};") |> bind
            }
        }
        trace.after++
        tell("end;") |> bind
        return trace.completed
    }
    let failed = fail_at >= 0 && fail_at < count
    let successful = failed ? fail_at : count
    assert(trace.calls == (failed ? fail_at + 1 : count))
    assert(trace.completed == successful && trace.after == (failed ? 0 : 1))
    assert(trace.condition == (use_while ? (failed ? fail_at + 1 : count + 1) : 0))
    assert(trace.source == (use_while ? 0 : 1))
    var expected = "begin;"
    for (i in range(successful)) { expected += "try{i};done{i};" }
    if (failed) {
        expected += "try{fail_at};FAIL;"
        assert(output.result is err && (output.result as err) == "failure {fail_at}")
    } else {
        expected += "end;"
        assert(output.result is ok && (output.result as ok) == count)
    }
    assert(output.log == expected)
}
def test_nested(fail_at : int) {
    var trace : Trace
    let output = computation(WriterResultBuilder()) {
        tell("outer;") |> bind
        for (i in range(2)) {
            var j = 0
            while (j < 2) {
                step(trace, i*2+j, fail_at) |> bind
                trace.completed++
                j++
            }
        }
    }
    assert(trace.calls == (fail_at < 0 ? 4 : fail_at + 1))
    assert(trace.completed == (fail_at < 0 ? 4 : fail_at))
    var expected = "outer;"
    for (i in range(fail_at < 0 ? 4 : fail_at + 1)) { expected += "try{i};" }
    if (fail_at >= 0) {
        expected += "FAIL;"
        assert(output.result is err && (output.result as err) == "failure {fail_at}")
    } else { assert(output.result is ok) }
    assert(output.log == expected)
}
def test_lifts() {
    let empty_value = computation(WriterResultBuilder()) {}
    assert(empty_value.result is ok && empty_value.log == "")
    let unit_value = computation(WriterResultBuilder()) { tell("unit;") |> bind }
    assert(unit_value.result is ok && unit_value.log == "unit;")
    let plain = computation(WriterResultBuilder()) {
        let n = result_ok(7) |> bind
        return "n={n}"
    }
    assert(plain.result is ok && (plain.result as ok) == "n=7" && plain.log == "")
    var skipped = 0
    let plain_error = computation(WriterResultBuilder()) {
        tell("before;") |> bind
        result_error("plain", type<int>) |> bind
        skipped++
        tell("WRONG;") |> bind
        return "unreachable"
    }
    assert(plain_error.result is err && (plain_error.result as err) == "plain")
    assert(plain_error.log == "before;" && skipped == 0)
    let forwarded = computation(WriterResultBuilder()) {
        tell("before;") |> bind
        return writer_result_error("forwarded", type<string>, "failure;") |> return_from
    }
    assert(forwarded.result is err && forwarded.log == "before;failure;")
    let forwarded_plain = computation(WriterResultBuilder()) {
        tell("before;") |> bind
        return result_error("plain", type<int>) |> return_from
    }
    assert(forwarded_plain.result is err && forwarded_plain.log == "before;")
    let forwarded_tell = computation(WriterResultBuilder()) { return tell("last;") |> return_from }
    assert(forwarded_tell.result is ok && forwarded_tell.log == "last;")
    let nested = computation(WriterResultBuilder()) {
        tell("outer;") |> bind
        let n = computation(WriterResultBuilder()) {
            tell("inner;") |> bind
            return 42
        } |> bind
        tell("after;") |> bind
        return n
    }
    assert(nested.result is ok && (nested.result as ok) == 42 && nested.log == "outer;inner;after;")
    let branch = computation(WriterResultBuilder()) {
        tell("before;") |> bind
        if (true) { return writer_result_ok(12, "selected;") |> return_from }
        else { return writer_result_error("WRONG", type<int>, "WRONG;") |> return_from }
    }
    assert(branch.result is ok && branch.log == "before;selected;")
    var trace : Trace
    let stopped = computation(WriterResultBuilder()) {
        if (true) { step(trace, 0, 0) |> bind }
        for (i in loop_source(trace, 3)) { tell("WRONG;") |> bind }
        while (loop_condition(trace, 0, 1)) { tell("WRONG;") |> bind }
        return 42
    }
    assert(stopped.result is err && stopped.log == "try0;FAIL;")
    assert(trace.calls == 1 && trace.source == 0 && trace.condition == 0)
    let independent = computation(WriterResultBuilder()) { return 1 }
    assert(independent.log == "")
}
[export]
def main() {
    for (fail_at in range(-1, 3)) { test_linear(fail_at) }
    for (count in range(5)) {
        for (fail_at in range(-1, count+1)) {
            test_loops(count, fail_at, false)
            test_loops(count, fail_at, true)
        }
    }
    for (fail_at in range(-1, 4)) { test_nested(fail_at) }
    test_lifts()
    print("writer/result checks OK: first failure, retained logs, exact order, lifts, branches, nested loops\n")
}
