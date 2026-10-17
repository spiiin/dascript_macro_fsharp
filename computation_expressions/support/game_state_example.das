options gen2
module game_state_example public
require ../lib/computation.das public
require math

struct GameState {
    health : int
    gold : int
    turns : int
}

// Reusable function: each call starts with its own initial state.
def play_turn(initial : GameState; damage, reward : int) {
    return computation(StateBuilder(initial)) {
        var game = state_get() |> bind
        game.health = max(0, game.health - damage)
        game.turns++
        state_put(game) |> bind

        if (game.health > 0) {
            for (coin in range(reward)) {
                var current = state_get() |> bind
                current.gold++
                state_put(current) |> bind
            }
        }
        let final_state = state_get() |> bind
        return final_state.health > 0
    }
}

