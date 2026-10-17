options gen2
require ../support/game_transaction.das
[export]
def main() {
    let bad = computation(StateResultBuilder(AdventureState())) {
        state_result_ok(1, 42) |> bind
    }
    print("{bad}\n")
}
