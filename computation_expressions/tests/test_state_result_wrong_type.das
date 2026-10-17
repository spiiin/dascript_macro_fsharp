options gen2
require ../support/game_transaction.das
[export]
def main() {
    let bad = computation(StateResultBuilder(AdventureState())) { state_put(42) |> bind }
    print("{bad}\n")
}
