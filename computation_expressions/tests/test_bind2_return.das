options gen2
require ../lib/computation.das
require ../lib/validation_builder.das

var maps=0
var calls=0
var order=""
def failed_result(n:int) { calls++; order+="{n}"; return result_error("error{n}",type<int>) }
def map_pair(p:tuple<first:int;second:int>) { maps++; return (sum=p.first+p.second) }
[export]
def main() {
    let rejected=computation(ResultBuilder()) { let p=failed_result(1) |> and_bind(failed_result(2)) |> bind; return map_pair(p) }
    assert(rejected is err && (rejected as err)=="error1" && maps==0 && calls==2 && order=="12")
    let absent=computation(OptionBuilder()) { let p=some(1) |> and_bind(none(type<int>)) |> bind; return map_pair(p) }
    assert(absent is none && maps==0)
    let invalid=computation(ValidationBuilder()) { let p=validation_error("left",type<int>) |> and_bind(validation_error("right",type<int>)) |> bind; return map_pair(p) }
    assert(invalid is invalid && (invalid as invalid).messages=="left\nright" && (invalid as invalid).count==2 && maps==0)
    let resultFast=computation(ResultBuilder()) { let p=result_ok(1) |> and_bind(result_ok(2)) |> bind; return map_pair(p) }
    let resultSlow=computation(ResultBuilder()) { let p=result_ok(1) |> and_bind(result_ok(2)) |> bind; let unused=0; return map_pair(p) }
    assert((typeinfo typename(resultFast))==(typeinfo typename(resultSlow)) && "{resultFast}"=="{resultSlow}")
    let optionFast=computation(OptionBuilder()) { let p=some(1) |> and_bind(some(2)) |> bind; return map_pair(p) }
    let optionSlow=computation(OptionBuilder()) { let p=some(1) |> and_bind(some(2)) |> bind; let unused=0; return map_pair(p) }
    assert((typeinfo typename(optionFast))==(typeinfo typename(optionSlow)) && "{optionFast}"=="{optionSlow}")
    let validationFast=computation(ValidationBuilder()) { let p=validation_ok(1) |> and_bind(validation_ok(2)) |> bind; return map_pair(p) }
    let validationSlow=computation(ValidationBuilder()) { let p=validation_ok(1) |> and_bind(validation_ok(2)) |> bind; let unused=0; return map_pair(p) }
    assert((typeinfo typename(validationFast))==(typeinfo typename(validationSlow)) && "{validationFast}"=="{validationSlow}")
    assert(maps==6)
    print("bind2_return value checks OK\n")
}
