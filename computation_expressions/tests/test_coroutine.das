options gen2
require ../lib/computation_macro.das
require ../lib/coroutine_builder.das
require ../lib/deferred_computation.das
require daslib/rtti
require daslib/strings_boost
var trace=""
var opened=0
var closed=0
var closeOrder=""
struct Buffer {id:int; data:array<int>}
def acquire(id:int) {
    var value:Buffer
    value.id=id
    value.data <- [10,20]
    opened++
    return <- value
}
def ce_dispose(var value:Buffer) {
    assert(value.id!=0)
    closed++
    closeOrder+="{value.id}"
    delete value
}
def expect_tick(var task:iterator<CoroutineFrame>; expected:bool) {
    let active=coroutine_resume(task)
    assert(active==expected)
}
def timing() {
    trace=""
    var inscope task <- computation(CoroutineBuilder()) {
        trace+="a"
        yield wait_frames(0)
        trace+="b"
        yield next_frame()
        trace+="c"
        yield wait_frames(2)
        trace+="d"
    }
    assert(trace=="")
    expect_tick(task,true); assert(trace=="ab")
    expect_tick(task,true); assert(trace=="abc")
    expect_tick(task,true); assert(trace=="abc")
    expect_tick(task,false); assert(trace=="abcd")
    expect_tick(task,false)
    coroutine_cancel(task)
    var inscope empty <- computation(CoroutineBuilder()) {}
    expect_tick(empty,false)
    trace=""
    var inscope looping <- computation(CoroutineBuilder()) {
        var index=0
        while (index<2) {
            trace+="{index}"
            yield next_frame()
            index++
        }
    }
    expect_tick(looping,true); assert(trace=="0")
    expect_tick(looping,true); assert(trace=="01")
    expect_tick(looping,false)
}
def owned_script(fail:bool) {
    return <- computation(CoroutineBuilder()) {
        var resource & = acquire(1) |> use_resource
        yield next_frame()
        resource.data |> push(30)
        assert(length(resource.data)==3)
        if (fail) {panic("script failed")}
        yield next_frame()
    }
}
def resources() {
    let baseline=heap_bytes_allocated()
    let before=opened
    {
        var inscope unused <- owned_script(false)
        coroutine_cancel(unused)
        expect_tick(unused,false)
    }
    assert(opened==before)
    {
        var inscope completed <- owned_script(false)
        expect_tick(completed,true)
        assert(opened==closed+1)
        expect_tick(completed,true)
        expect_tick(completed,false)
        assert(opened==closed)
    }
    {
        var inscope cancelled <- owned_script(false)
        expect_tick(cancelled,true)
        coroutine_cancel(cancelled)
        coroutine_cancel(cancelled)
        expect_tick(cancelled,false)
        assert(opened==closed)
    }
    {
        var inscope broken <- owned_script(false)
        for (frame in broken) {break}
        assert(opened==closed)
    }
    {
        var inscope failed <- owned_script(true)
        expect_tick(failed,true)
        var caught=false
        try {let active=coroutine_resume(failed)} recover {
            caught=true
            assert(starts_with(this_context().last_exception,"script failed"))
        }
        assert(caught && opened==closed)
        expect_tick(failed,false)
    }
    {
        var inscope invalid <- computation(CoroutineBuilder()) {
            var resource & = acquire(1) |> use_resource
            yield wait_frames(-1)
        }
        var caught=false
        try {let active=coroutine_resume(invalid)} recover {
            caught=true
            assert(starts_with(this_context().last_exception,"wait_frames:"))
        }
        assert(caught && opened==closed)
    }
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
def child(fail:bool) {
    return <- computation(CoroutineBuilder()) {
        var resource & = acquire(2) |> use_resource
        trace+="child;"
        yield wait_frames(2)
        if (fail) {panic("child failed")}
        trace+="child done;"
    }
}
def parent(fail:bool) {
    return <- computation(CoroutineBuilder()) {
        var resource & = acquire(1) |> use_resource
        child(fail) |> yield_from
        trace+="parent done;"
    }
}
def nesting() {
    let baseline=heap_bytes_allocated()
    for (mode in range(3)) {
        trace=""; closeOrder=""
        var inscope task <- parent(mode==2)
        expect_tick(task,true)
        assert(trace=="child;" && opened==closed+2)
        if (mode==0) {coroutine_cancel(task)}
        else {
            expect_tick(task,true)
            if (mode==1) {
                expect_tick(task,false)
                assert(trace=="child;child done;parent done;")
            } else {
                var caught=false
                try {let active=coroutine_resume(task)} recover {caught=true}
                assert(caught && trace=="child;")
            }
        }
        assert(opened==closed && closeOrder=="21")
    }
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
def saved_script() {
    var inscope data <- [7,8]
    return <- deferred(CoroutineBuilder(),data) $(snapshot) {
        var resource & = acquire(3) |> use_resource
        let item=snapshot |> bind
        trace+="{item};"
        yield next_frame()
    }
}
def deferred_runs() {
    let baseline=heap_bytes_allocated()
    trace=""
    {
        var inscope saved <- saved_script()
        var inscope left <- run_deferred(saved)
        var inscope right <- run_deferred(saved)
        delete saved
        assert(trace=="")
        expect_tick(left,true)
        expect_tick(right,true)
        assert(trace=="7;7;")
        coroutine_cancel(left)
        expect_tick(right,true)
        expect_tick(right,false)
        assert(trace=="7;7;8;" && opened==closed)
    }
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
[export]
def main() {
    for (round in range(3)) {
        timing()
        resources()
        nesting()
        deferred_runs()
    }
    print("coroutine checks OK\n")
}
