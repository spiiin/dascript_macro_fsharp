options gen2
require ../support/game_state_example.das
[export]
def main() {
    let initial = GameState(health=100, gold=5, turns=0)
    let adventure = computation(StateBuilder(initial)) {
        let before = state_get() |> bind
        let survived = play_turn(before, 25, 3) |> bind
        let after = state_get() |> bind
        assert(survived && after.health == 75 && after.gold == 8)

        var potions = 2
        while (potions > 0) {
            var game = state_get() |> bind
            game.health += 5
            state_put(game) |> bind
            potions--
        }
        let final_state = state_get() |> bind
        return "health={final_state.health}, gold={final_state.gold}"
    }
    assert(initial.health == 100 && initial.gold == 5 && initial.turns == 0)
    assert(adventure.state.health == 85 && adventure.state.gold == 8 && adventure.state.turns == 1)
    print("{adventure.value}; turns={adventure.state.turns}\n")
    print("state demo OK\n")
}
