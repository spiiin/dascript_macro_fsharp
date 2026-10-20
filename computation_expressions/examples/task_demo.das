options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das

// The host can keep rendering/processing events between task_poll calls.
def load_player(accepted:bool) {
    return <- computation(TaskResultBuilder(type<string>)) {
        let name=task_after_polls(2,result_ok("Alice")) |> bind
        let health=task_after_polls(1,accepted ? result_ok(85) : result_error("access denied",type<int>)) |> bind
        return "{name}: health={health}"
    }
}
[export]
def main() {
    var inscope good <- load_player(true)
    var inscope bad <- load_player(false)
    var active=true
    var frame=0
    while(active) {
        frame++
        let first=task_poll(good)
        let second=task_poll(bad)
        active=first==TaskStatus.Waiting || second==TaskStatus.Waiting
        print("Frame {frame}: other host work can run here\n")
    }
    let player=task_value(good)
    let rejected=task_value(bad)
    verify(player is ok && player as ok=="Alice: health=85")
    verify(rejected is err && rejected as err=="access denied")
    print("{player as ok}\n{rejected as err}\nTask demo OK\n")
}
