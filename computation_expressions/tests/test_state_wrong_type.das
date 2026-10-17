options gen2
require ../support/game_state_example.das
[export]
def main() {
    let invalid = computation(StateBuilder(GameState())) {
        state_put(42) |> bind
    }
    print("{invalid}\n")
}
