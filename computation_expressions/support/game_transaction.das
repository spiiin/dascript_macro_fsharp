options gen2
module game_transaction public
require ../lib/computation.das public
struct AdventureState { health : int; gold : int; potions : int; turns : int }

def check_alive(health : int) : variant<ok : CeUnit; error : string> {
    if (health <= 0) { return variant<ok : CeUnit; error : string>(error="hero defeated") }
    return ce_zero(ResultBuilder())
}
// Purchase, use a potion, take damage, then validate: failure rolls back all steps.
def adventure_turn(initial : AdventureState; damage : int; var reached : int&) {
    return computation(StateResultBuilder(initial)) {
        var game = state_get() |> bind
        if (game.gold < 10) { result_error("not enough gold", type<int>) |> bind }
        game.gold -= 10
        game.potions++
        state_put(game) |> bind
        reached++

        var healed = state_get() |> bind
        healed.potions--
        healed.health += 20
        healed.turns++
        state_put(healed) |> bind
        reached++

        var injured = state_get() |> bind
        injured.health -= damage
        state_put(injured) |> bind
        check_alive(injured.health) |> bind
        reached++
        return "turn completed"
    }
}
