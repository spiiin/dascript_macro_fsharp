options gen2
require ../lib/computation.das
require ../lib/validation_builder.das

[export]
def main() {
    let result=computation(ResultBuilder()) {
        let level=result_ok(12) |> bind
        return "Level {level}"
    }
    let optional=computation(OptionBuilder()) { let value=some(4) |> bind; return value*2 }
    let validated=computation(ValidationBuilder()) {
        let fields=validation_ok("Mage") |> and_bind(validation_ok(12)) |> bind
        return "{fields.first}:{fields.second}"
    }
    var inscope damage <- computation(ListBuilder()) {
        let stats=fixed_array(10,20,30) |> bind
        return stats*2
    }
    assert(result is ok && (result as ok)=="Level 12")
    assert(optional is some && (optional as some)==8)
    assert(validated is valid && (validated as valid)=="Mage:12")
    assert(length(damage)==3 && damage[0]==20 && damage[2]==60)
    print("bind_return demo OK\n")
}
