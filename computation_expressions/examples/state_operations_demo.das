options gen2
require ../lib/computation.das
struct Hero {health:int;gold:int}
[export]
def main() {
    let turn=computation(StateBuilder(Hero(health=100,gold=5))) {
        state_modify($(hero:Hero) {return Hero(health=hero.health-25,gold=hero.gold+3)}) |> bind
        let health=state_gets($(hero:Hero) {return hero.health}) |> bind
        return "После удара: {health}"
    }
    assert(turn.state.health==75 && turn.state.gold==8)
    print("{turn.value}; gold={turn.state.gold}\nState operations demo OK\n")
}
