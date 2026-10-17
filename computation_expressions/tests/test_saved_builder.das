options gen2
require ../lib/computation.das
require ../lib/reader_result_builder.das
require ../lib/deferred_computation.das
require ../support/protocol_test_builders.das

var factories=0
struct Rules {scale:int=3}
def make_saved() {factories++; return ReaderResultBuilder(Rules())}
def from_parameter(builder:auto) {
    return computation(builder) {return 42}
}
def saved_sequence() {
    let builder=SequenceBuilder()
    return <- computation(builder) {for (i in range(3)) {yield i+10}}
}
[export]
def main() {
    let builder=make_saved()
    let first=computation(builder) {let env=reader_ask() |> bind; return env.scale*2}
    let second=computation(builder) {let env=reader_ask() |> bind; return env.scale*3}
    assert(first as ok==6 && second as ok==9 && factories==1)
    let reader=ReaderBuilder(7)
    let read=computation(reader) {let env=reader_ask() |> bind; return env+1}
    assert(read.value==8)
    let parameter=from_parameter(reader)
    assert(parameter.value==42)
    let wrapped=(builder=ReaderBuilder(4))
    let field=computation(wrapped.builder) {let env=reader_ask() |> bind; return env}
    assert(field.value==4)
    let resultBuilder=ResultBuilder()
    let result=computation(resultBuilder) {let value=result_ok(20) |> bind; return value+2}
    assert(result as ok==22)
    var stateBuilder=StateResultBuilder(10)
    let changed=computation(stateBuilder) {state_put(30) |> bind; return 1}
    let original=computation(stateBuilder) {let state=state_get() |> bind; return state}
    assert(changed.state==30 && original.state==10 && original.result as ok==10 && stateBuilder.state==10)
    let listBuilder=ListBuilder()
    var inscope values <- computation(listBuilder) {let x=fixed_array(1,2) |> bind; return x*3}
    assert(length(values)==2 && values[0]==3 && values[1]==6)
    let owned=MoveResultBuilder()
    var inscope moved <- computation(owned) {return <- [3,4]}
    assert(moved is ok && length(moved as ok)==2)
    var inscope stream <- saved_sequence()
    var sum=0
    for (item in stream) {sum+=item}
    assert(sum==33)
    let custom=custom_sequence()
    var inscope external <- computation(custom) {yield "saved"}
    for (item in external) {assert(item=="saved")}
    assert(sequenceConstructors==1 && sequenceRuns==1 && protocolCalls==0)
    var inscope delayed <- deferred(builder,5) $(snapshot) {
        let env=reader_ask() |> bind
        return env.scale+snapshot
    }
    let a=run_deferred(delayed)
    let b=run_deferred(delayed)
    assert(a as ok==8 && b as ok==8 && factories==1)
    print("saved builder checks OK\n")
}
