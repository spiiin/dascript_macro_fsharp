options gen2
require ../lib/computation.das

def checked_number(value : int) : $Result<int;string> {
    if (value < 0) { return result_error("negative number", type<int>) }
    return result_ok(value)
}

[export]
def main() {
    let result = computation(ResultBuilder()) {
        let health = checked_number(100) |> bind
        let damage = checked_number(15) |> bind
        let remaining = health - damage
        return remaining
    }
    assert(result is ok)
    print("Result: {result as ok}\n")

    let option = computation(OptionBuilder()) {
        let name = some("Alice") |> bind
        return "Hello, {name}"
    }
    assert(option is some)
    print("Option: {option as some}\n")

    var skipped = 0
    let failed = computation(ResultBuilder()) {
        let number = checked_number(-1) |> bind
        skipped++
        return number + 1
    }
    let absent = computation(OptionBuilder()) {
        let number = none(type<int>) |> bind
        skipped++
        return number + 1
    }
    assert(failed is err && absent is none && skipped == 0)
    print("Error: {failed as err}; None: true; skipped steps executed: {skipped}\n")
    print("computation demo OK\n")
}
