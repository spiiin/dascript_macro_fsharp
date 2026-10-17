options gen2
require ../lib/computation.das

struct GameState { gold:int=10; experience:int=0 }
[export]
def main() {
    let trained=computation(StateBuilder(GameState())) {
        state_put(GameState(gold=7,experience=5)) |> bind
        let player=state_get() |> bind
        return "XP: {player.experience}"
    }
    assert(trained.state.gold==7 && trained.value=="XP: 5")
    let rejected=computation(StateResultBuilder(GameState())) {
        state_put(GameState(gold=0,experience=100)) |> bind
        let reward=result_error("Quest is incomplete",type<int>) |> bind
        return reward*2
    }
    assert(rejected.result is error && rejected.state.gold==10 && rejected.state.experience==0)
    let journal=computation(WriterResultBuilder()) {
        tell("Quest opened; ") |> bind
        let reward=writer_result_ok(25,"reward checked; ") |> bind
        return reward*2
    }
    assert(journal.result is ok && (journal.result as ok)==50)
    assert(journal.log=="Quest opened; reward checked; ")
    print("{trained.value}; rollback gold={rejected.state.gold}; reward={journal.result as ok}\n")
    print("effect bind_return demo OK\n")
}
