options gen2
require ../lib/computation.das
require ../lib/state_writer_result_builder.das
require ../lib/deferred_computation.das
var calls=0
struct Hero {hp:int; gold:int}
[export]
def main() {
    let turn=computation(StateBuilder(Hero(hp=100,gold=5))) {
        state_modify($(hero:Hero) {calls++;return Hero(hp=hero.hp-25,gold=hero.gold)}) |> bind
        let health=state_gets($(hero:Hero) {calls++;return hero.hp}) |> bind
        state_modify($(hero:Hero) {return Hero(hp=hero.hp+10,gold=hero.gold)}) |> bind
        return health
    }
    assert(turn.value==75 && turn.state.hp==85 && calls==2)
    let rollback=computation(StateResultBuilder(100)) {
        state_modify($(hp:int) {return hp-25}) |> bind
        let hp=state_gets($(value:int) {return value}) |> bind
        if(hp<100){result_error("rollback",type<CeUnit>) |> bind}
        return hp
    }
    assert(rollback.result is err && rollback.state==100)
    let logged=computation(StateWriterResultBuilder(5)) {
        state_modify($(n:int){return n+2}) |> bind
        tell("modified;") |> bind
        let doubled=state_gets($(n:int){return n*2}) |> bind
        return doubled
    }
    assert(logged.state==7 && logged.result as ok==14 && logged.log=="modified;")
    var inscope task <- deferred(StateBuilder(1)) {
        for(i in range(3)){state_modify($(n:int){return n+1}) |> bind}
        let n=state_gets($(value:int){return value*2}) |> bind
        return n
    }
    let first=run_deferred(task);let second=run_deferred(task)
    assert(first.value==8 && second.value==8 && first.state==4)
    print("State operations OK\n")
}
