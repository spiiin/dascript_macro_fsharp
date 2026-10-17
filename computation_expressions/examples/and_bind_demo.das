options gen2
require ../lib/computation.das
require ../lib/validation_builder.das

[export]
def main() {
    let fields = computation(ValidationBuilder()) {
        let pair = (validation_error("Name is empty",type<string>)
            |> and_bind(validation_error("Level must be positive",type<int>)) |> bind)
        return "{pair.first}: {pair.second}"
    }
    assert(fields is invalid && (fields as invalid).count == 2)
    print("Validation:\n{(fields as invalid).messages}\n")
    let result = computation(ResultBuilder()) {
        let pair = result_ok("Mage") |> and_bind(result_ok(12)) |> bind
        return "{pair.first}, level {pair.second}"
    }
    assert(result is ok)
    print("Result: {result as ok}\n")
    let optional = computation(OptionBuilder()) {
        let pair = some("Sword") |> and_bind(some(3)) |> bind
        return "{pair.first} +{pair.second}"
    }
    assert(optional is some)
    print("Option: {optional as some}\n")
    var inscope loadouts <- computation(ListBuilder(type<string>)) {
        let pair = ["Mage","Knight"] |> and_bind(["Fire","Ice"]) |> bind
        return "{pair.first}/{pair.second}"
    }
    assert(length(loadouts)==4)
    for (loadout in loadouts) { print("Loadout: {loadout}\n") }
    print("and_bind demo OK\n")
}

