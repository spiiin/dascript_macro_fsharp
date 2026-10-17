options gen2
module game_logged_transaction public
require ../lib/computation_macro.das public
require ../lib/state_writer_result_builder.das public

struct LoggedHero {health:int=50; gold:int=30}

def buy_potion(initial:LoggedHero) {
    return computation(StateWriterResultBuilder(initial)) {
        let hero=state_get() |> bind
        tell("buy potion; ") |> bind
        if (hero.gold<10) {result_error("not enough gold",type<CeUnit>) |> bind}
        state_put(LoggedHero(health=hero.health+20,gold=hero.gold-10)) |> bind
        return "potion"
    }
}

def logged_turn(initial:LoggedHero; damage:int) {
    return computation(StateWriterResultBuilder(initial)) {
        tell("start; ") |> bind
        buy_potion(initial) |> bind
        let hero=state_get() |> bind
        tell("damage {damage}; ") |> bind
        state_put(LoggedHero(health=hero.health-damage,gold=hero.gold)) |> bind
        if (damage>=hero.health) {
            result_error("hero defeated",type<CeUnit>) |> bind
        }
        tell("commit; ") |> bind
        return "turn complete"
    }
}
