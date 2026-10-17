options gen2
require ../lib/computation_macro.das
require ../lib/coroutine_builder.das
var position=0
var journal=""
def patrol() {
    return <- computation(CoroutineBuilder()) {
        let waypoint=fixed_array(10,20) |> bind
        position=waypoint
        journal+="arrive {waypoint}; "
        yield wait_frames(2)
        journal+="leave {waypoint}; "
    }
}
[export]
def main() {
    var inscope task <- computation(CoroutineBuilder()) {
        journal+="start; "
        yield next_frame()
        patrol() |> yield_from
        journal+="done; "
    }
    assert(journal=="")
    var frame=0
    while (true) {
        frame++
        let active=coroutine_resume(task)
        print("frame {frame}: position={position}, active={active}\n")
        if (!active) {break}
    }
    assert(frame==6 && position==20)
    assert(journal=="start; arrive 10; leave 10; arrive 20; leave 20; done; ")
    print("{journal}\ncoroutine demo OK\n")
}
