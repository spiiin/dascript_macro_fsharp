options gen2
require ../lib/computation_macro.das
require ../lib/coroutine_scheduler.das

def npc(name:string; fail:bool) {
    return <- computation(CoroutineBuilder()) {
        print("{name}: start\n")
        yield next_frame()
        if (fail) {panic("{name}: path unavailable")}
        print("{name}: move\n")
        yield next_frame()
        print("{name}: done\n")
    }
}
[export]
def main() {
    var inscope scheduler:CoroutineScheduler
    let guard=coroutine_spawn(scheduler,npc("guard",false))
    let scout=coroutine_spawn(scheduler,npc("scout",false))
    let enemy=coroutine_spawn(scheduler,npc("enemy",true))
    let first=coroutine_tick(scheduler)
    assert(first==3)
    let cancelled=coroutine_cancel(scheduler,scout)
    assert(cancelled)
    let second=coroutine_tick(scheduler)
    assert(second==1)
    let third=coroutine_tick(scheduler)
    assert(third==0)
    verify(coroutine_status(scheduler,guard)==CoroutineStatus.Completed)
    verify(coroutine_status(scheduler,scout)==CoroutineStatus.Cancelled)
    verify(coroutine_status(scheduler,enemy)==CoroutineStatus.Failed)
    print("Enemy error: {coroutine_error(scheduler,enemy)}\n")
    print("coroutine scheduler demo OK\n")
}

