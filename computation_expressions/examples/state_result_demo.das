options gen2
require ../support/game_transaction.das
[export]
def main() {
    let initial = AdventureState(health=50, gold=30, potions=2, turns=0)
    var reached = 0
    let success = adventure_turn(initial, 10, reached)
    assert(success.result is ok && reached == 3)
    assert(success.state.health == 60 && success.state.gold == 20 && success.state.potions == 2 && success.state.turns == 1)
    reached = 0
    let failed = adventure_turn(initial, 100, reached)
    assert(failed.result is error && (failed.result as error) == "hero defeated")
    assert(reached == 2)
    assert(failed.state.health == 50 && failed.state.gold == 30 && failed.state.potions == 2 && failed.state.turns == 0)
    assert(initial.health == 50 && initial.gold == 30)
    print("Success: health={success.state.health}, gold={success.state.gold}, turns={success.state.turns}\n")
    print("Error: {failed.result as error}; rollback: health={failed.state.health}, gold={failed.state.gold}, turns={failed.state.turns}\n")
    print("Reached steps before error: {reached} (external counter is not rolled back)\n")
    print("state/result demo OK\n")
}
