options gen2
require ../lib/computation.das

def validate(value : int) {
    if (value == 3) { return result_error("rejected 3", type<int>) }
    return result_ok(value)
}
def find_value(value : int) {
    if (value == 3) { return none(type<int>) }
    return some(value)
}
[export]
def main() {
    var accepted = 0
    var after_result = 0
    let result = computation(ResultBuilder()) {
        for (i in range(5)) {
            if (i % 2 == 0) {
                let value = validate(i) |> bind
                print("accepted even {value}\n")
            } else {
                validate(i) |> bind // Check success; discard the payload.
            }
            accepted++
        }
        after_result++
        return accepted
    }
    assert(result is error && (result as error) == "rejected 3")
    assert(accepted == 3 && after_result == 0)
    print("Result: {result as error}; completed={accepted}; after={after_result}\n")

    var i = 0
    var after_option = 0
    let option = computation(OptionBuilder()) {
        while (i < 5) {
            find_value(i) |> bind
            i++
        }
        after_option++
        return i
    }
    assert(option is none && i == 3 && after_option == 0)
    print("Option: None; completed={i}; after={after_option}\n")

    let description = computation(ResultBuilder()) {
        let n = result_ok(4) |> bind
        if (n > 0) { return "positive" }
        else { return "nonpositive" }
    }
    assert(description is ok && (description as ok) == "positive")
    // An empty scope computes successful Unit, not failure/absence.
    let empty_result = computation(ResultBuilder()) {}
    let empty_option = computation(OptionBuilder()) {}
    assert(empty_result is ok && empty_option is some)
    print("control flow demo OK\n")
}

