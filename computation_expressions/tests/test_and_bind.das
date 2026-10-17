options gen2
require ../lib/computation.das
require ../lib/validation_builder.das

var calls = 0
var order = ""
var continued = 0
var constructors = 0
def result_source(id:int; fail:bool) {
    calls++
    order += "{id}"
    if (fail) { return result_error("error{id}", type<int>) }
    return result_ok(id)
}
def option_source(id:int; fail:bool) {
    calls++
    if (fail) { return none(type<int>) }
    return some(id)
}
def counted_builder() { constructors++; return ResultBuilder() }
[export]
def main() {
    let rejected = computation(counted_builder()) {
        let pair = result_source(1,true) |> and_bind(result_source(2,true)) |> bind
        continued++
        return pair.first + pair.second
    }
    assert(rejected is error && (rejected as error) == "error1")
    assert(calls == 2 && order == "12" && continued == 0 && constructors == 1)
    let rightError = computation(ResultBuilder()) {
        let p = result_ok(1) |> and_bind(result_error("right", type<string>)) |> bind
        return p.second
    }
    assert(rightError is error && (rightError as error) == "right")
    let success = computation(ResultBuilder()) {
        let p = result_ok(3) |> and_bind(result_ok("mage")) |> and_bind(result_ok(4)) |> bind
        return "{p.first.second}:{p.first.first+p.second}"
    }
    assert(success is ok && (success as ok) == "mage:7")
    let skippedGroup = computation(ResultBuilder()) {
        result_error("before group", type<int>) |> bind
        result_source(3,false) |> and_bind(result_source(4,false)) |> bind
        return 0
    }
    assert(skippedGroup is error && calls == 2)
    let absent = computation(OptionBuilder()) {
        option_source(1,true) |> and_bind(option_source(2,false)) |> bind
        continued++
        return 1
    }
    assert(absent is none && calls == 4 && continued == 0)
    let absentRight = computation(OptionBuilder()) { some(1) |> and_bind(none(type<string>)) |> bind; return 1 }
    assert(absentRight is none)
    let present = computation(OptionBuilder()) {
        let p = some(1) |> and_bind(some("name")) |> bind
        return p.second
    }
    assert(present is some && (present as some) == "name")
    let invalid = computation(ValidationBuilder()) {
        let p = validation_error("name",type<string>) |> and_bind(validation_error("level",type<int>)) |> and_bind(validation_error("class",type<string>)) |> bind
        continued++
        return p.second
    }
    assert(invalid is invalid && (invalid as invalid).count == 3)
    assert((invalid as invalid).messages == "name\nlevel\nclass" && continued == 0)
    let valid = computation(ValidationBuilder()) {
        let p = validation_ok("hero") |> and_bind(validation_ok(12)) |> bind
        return "{p.first}:{p.second}"
    }
    assert(valid is valid && (valid as valid) == "hero:12")
    var iterations = 0
    let loop = computation(ResultBuilder()) {
        for (i in range(5)) { iterations++; result_ok(i) |> and_bind(result_error("loop",type<int>)) |> bind }
        continued++
        return 1
    }
    assert(loop is error && iterations == 1 && continued == 0)
    let beforeTriple = calls
    order = ""
    let tripleError = computation(ResultBuilder()) {
        result_source(1,true) |> and_bind(result_source(2,false)) |> and_bind(result_source(3,true)) |> bind
        continued++
        return 0
    }
    assert(tripleError is error && (tripleError as error)=="error1")
    assert(calls==beforeTriple+3 && order=="123" && continued==0)
    print("and_bind value checks OK\n")
}

