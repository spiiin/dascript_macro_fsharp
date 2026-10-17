options gen2
require ../lib/computation_macro.das
require ../lib/validation_builder.das

var checks = 0
var after = 0
var closes = 0
struct Resource {}
def ce_dispose(var resource : Resource) { closes++ }
def checked(fail:bool; message:string) {
    checks++
    if (fail) { return validation_error(message, type<int>) }
    return validation_ok(10)
}
[export]
def main() {
    let both = computation(ValidationBuilder()) {
        let a = checked(true, "name")
        let b = checked(true, "level")
        let pair = a |> validation_zip(b) |> bind
        after++
        return pair.first + pair.second
    }
    assert(checks == 2 && after == 0)
    assert(both is invalid && (both as invalid).count == 2)
    assert((both as invalid).messages == "name\nlevel")
    let left = validation_error("left", type<int>) |> validation_zip(validation_ok("right"))
    let right = validation_ok(3) |> validation_zip(validation_error("right", type<string>))
    assert(left is invalid && (left as invalid).messages == "left" && (left as invalid).count == 1)
    assert(right is invalid && (right as invalid).messages == "right" && (right as invalid).count == 1)
    let three = both |> validation_zip(validation_error("class", type<string>))
    assert(three is invalid && (three as invalid).count == 3)
    assert((three as invalid).messages == "name\nlevel\nclass")
    let good = computation(ValidationBuilder()) {
        let pair = validation_ok(12) |> validation_zip(validation_ok("mage")) |> bind
        return "{pair.second}:{pair.first}"
    }
    assert(good is valid && (good as valid) == "mage:12")
    let nested = validation_ok(1) |> validation_zip(validation_ok("two")) |> validation_zip(validation_ok(3.0))
    assert(nested is valid && (nested as valid).first.second == "two" && (nested as valid).second == 3.0)
    let sequential = computation(ValidationBuilder()) {
        checked(true, "stop") |> bind
        checked(false, "not run") |> bind
        after++
        return 1
    }
    assert(sequential is invalid && checks == 3 && after == 0)
    var iterations = 0
    let loop = computation(ValidationBuilder()) {
        for (i in range(5)) {
            iterations++
            checked(i == 1, "iteration") |> bind
        }
        after++
        return "not run"
    }
    assert(loop is invalid && iterations == 2 && checks == 5 && after == 0)
    var attempts = 0
    let whileLoop = computation(ValidationBuilder()) {
        while (attempts < 5) { attempts++; checked(true, "while") |> bind }
        after++
        return 1
    }
    assert(whileLoop is invalid && attempts == 1 && after == 0)
    let branch = computation(ValidationBuilder()) {
        if (true) { validation_error("branch", type<int>) |> bind }
        after++
        return 1
    }
    assert(branch is invalid && after == 0)
    let unit = computation(ValidationBuilder()) {}
    assert(unit is valid)
    let forwarded = computation(ValidationBuilder()) { return three |> return_from }
    assert(forwarded is invalid && (forwarded as invalid).count == 3)
    let protected = computation(ValidationBuilder()) {
        let resource = Resource() |> use_resource
        try_finally($ { validation_error("cleanup", type<int>) |> bind }, $ { closes++ })
        after++
        return 1
    }
    assert(protected is invalid && closes == 2 && after == 0)
    let unhandled = computation(ValidationBuilder()) {
        try_with($ { return both |> return_from }, $(message:string) { after++; return 1 })
    }
    assert(unhandled is invalid && after == 0)
    let recovered = computation(ValidationBuilder()) {
        try_with($ {
            let resource = Resource() |> use_resource
            panic("native panic")
            return 1
        }, $(message:string) { return validation_error("recovered", type<int>) |> return_from })
    }
    assert(recovered is invalid && closes == 3 && (recovered as invalid).messages == "recovered")
    print("validation checks OK\n")
}
