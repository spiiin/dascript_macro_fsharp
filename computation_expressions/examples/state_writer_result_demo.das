options gen2
require ../support/game_logged_transaction.das
[export]
def main() {
    let initial=LoggedHero()
    let success=logged_turn(initial,10)
    assert(success.result is ok && success.state.health==60 && success.state.gold==20)
    assert(success.log=="start; buy potion; damage 10; commit; ")
    let failed=logged_turn(initial,100)
    assert(failed.result is err && failed.state.health==50 && failed.state.gold==30)
    assert(failed.log=="start; buy potion; damage 100; ")
    assert(initial.health==50 && initial.gold==30)
    print("Success: health={success.state.health}, gold={success.state.gold}\n{success.log}\n")
    print("Error: {failed.result as err}; rollback: health={failed.state.health}, gold={failed.state.gold}\n{failed.log}\n")
    print("state/writer/result demo OK\n")
}
