options gen2
require ../lib/computation_macro.das
require ../lib/coroutine_scheduler.das
var disposed=0
struct Resource {}
def ce_dispose(var resource:Resource) {disposed++}
def npc() {
    return <- computation(CoroutineBuilder()) {
        let resource=Resource() |> use_resource
        yield wait_frames(10)
    }
}
[export]
def main() {
    var caught=false
    try {
        coroutine_scope($(var scheduler:CoroutineScheduler) {
            let id=coroutine_spawn(scheduler,npc())
            let active=coroutine_tick(scheduler)
            assert(active==1)
            // A host error outside the task still closes all owned tasks.
            panic("game loop interrupted")
        })
    } recover {caught=true}
    assert(caught && disposed==1)
    print("coroutine scope demo OK\n")
}
