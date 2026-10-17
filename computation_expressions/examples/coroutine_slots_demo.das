options gen2
require ../lib/computation_macro.das
require ../lib/coroutine_scheduler.das
def one_frame() {
    return <- computation(CoroutineBuilder()) {yield next_frame()}
}
[export]
def main() {
    var inscope scheduler:CoroutineScheduler
    let old=coroutine_spawn(scheduler,one_frame())
    verify(coroutine_tick(scheduler)==1)
    verify(coroutine_tick(scheduler)==0)
    verify(coroutine_forget(scheduler,old))
    let current=coroutine_spawn(scheduler,one_frame())
    assert(current.slot==old.slot && current.generation!=old.generation)
    verify(!coroutine_valid(scheduler,old) && coroutine_valid(scheduler,current))
    print("Reused slot {current.slot}: generation {old.generation} -> {current.generation}\n")
    coroutine_close(scheduler)
    let removed=coroutine_prune(scheduler)
    assert(removed==1)
    print("coroutine slots demo OK\n")
}
