options gen2
require ../lib/computation.das
require ../lib/validation_builder.das
[export]
def main() {
    let hero=computation(ValidationBuilder()) {
        let fields=validation_ok("Mage") |> and_bind(validation_ok(12)) |> bind
        return "{fields.first}, level {fields.second}"
    }
    var inscope loadouts <- computation(ListBuilder(type<string>)) {
        let choice=["Mage","Knight"] |> and_bind(["Fire","Ice"]) |> bind
        return "{choice.first}/{choice.second}"
    }
    assert(hero is valid && (hero as valid)=="Mage, level 12")
    assert(length(loadouts)==4 && loadouts[0]=="Mage/Fire" && loadouts[3]=="Knight/Ice")
    print("bind2_return demo OK\n")
}
