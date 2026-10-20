options gen2
require ../lib/computation.das

struct Counts {
    first : int
    second : int
    third : int
    finished : int
    builder : int
}

def record(var counts : Counts; step : int) {
    if (step == 1) { counts.first++ }
    elif (step == 2) { counts.second++ }
    else { counts.third++ }
}
def result_step(var counts : Counts; step, fail_at : int) : $Result<int;string> {
    record(counts, step)
    if (step == fail_at) { return result_error("failure at {step}", type<int>) }
    return result_ok(step)
}
def option_step(var counts : Counts; step, fail_at : int) : $Option<int> {
    record(counts, step)
    if (step == fail_at) { return none(type<int>) }
    return some(step)
}
def finish(var counts : Counts; value : int) : string {
    counts.finished++
    return "sum={value}"
}
def result_builder(var counts : Counts) : ResultBuilder {
    counts.builder++
    return ResultBuilder()
}
def option_builder(var counts : Counts) : OptionBuilder {
    counts.builder++
    return OptionBuilder()
}

def test_result(fail_at : int) {
    var counts = default<Counts>
    let value = computation(result_builder(counts)) {
        let a : int = result_step(counts, 1, fail_at) |> bind
        var b = result_step(counts, 2, fail_at) |> bind
        b += a
        let c = result_step(counts, 3, fail_at) |> bind
        return finish(counts, b + c)
    }
    assert(counts.builder == 1 && counts.first == 1)
    assert(counts.second == (fail_at == 1 ? 0 : 1))
    assert(counts.third == (fail_at == 1 || fail_at == 2 ? 0 : 1))
    assert(counts.finished == (fail_at == 0 ? 1 : 0))
    if (fail_at == 0) {
        assert(value is ok && (value as ok) == "sum=6")
    } else {
        assert(value is err)
        let expected = "failure at {fail_at}"
        assert((value as err) == expected)
    }
    print("Result fail_at={fail_at}: steps={counts.first}/{counts.second}/{counts.third}, return={counts.finished}\n")
}

def test_option(fail_at : int) {
    var counts = default<Counts>
    let value = computation(option_builder(counts)) {
        let a = option_step(counts, 1, fail_at) |> bind
        let b = option_step(counts, 2, fail_at) |> bind
        let c = option_step(counts, 3, fail_at) |> bind
        return finish(counts, a + b + c)
    }
    assert(counts.builder == 1 && counts.first == 1)
    assert(counts.second == (fail_at == 1 ? 0 : 1))
    assert(counts.third == (fail_at == 1 || fail_at == 2 ? 0 : 1))
    assert(counts.finished == (fail_at == 0 ? 1 : 0))
    if (fail_at == 0) {
        assert(value is some && (value as some) == "sum=6")
    } else { assert(value is none) }
    print("Option fail_at={fail_at}: steps={counts.first}/{counts.second}/{counts.third}, return={counts.finished}\n")
}

[export]
def main() {
    for (fail_at in range(4)) {
        test_result(fail_at)
        test_option(fail_at)
    }
    let nested = computation(ResultBuilder()) {
        let inner = computation(OptionBuilder()) {
            let n = some(7) |> bind
            return n + 1
        }
        let number = result_ok(inner as some) |> bind
        return number * 2
    }
    assert(nested is ok && (nested as ok) == 16)
    let plain = computation(OptionBuilder()) { return 42 }
    assert(plain is some && (plain as some) == 42)
    let forwarded = computation(ResultBuilder()) {
        return result_error("forwarded", type<string>) |> return_from
    }
    assert(forwarded is err && (forwarded as err) == "forwarded")
    let forwarded_none = computation(OptionBuilder()) {
        return none(type<int>) |> return_from
    }
    assert(forwarded_none is none)
    print("computation checks OK\n")
}
