options gen2
require ../support/game_logged_transaction.das
require ../lib/computation.das
require ../lib/deferred_computation.das
require daslib/rtti
var after=0
var closed=0
var runs=0
struct Resource {}
def ce_dispose(var resource:Resource) {closed++}

def basics() {
    let zero=computation(StateWriterResultBuilder(10)) {}
    assert(zero.result is ok && zero.state==10 && zero.log=="")
    let value=computation(StateWriterResultBuilder(10)) {
        tell("a") |> bind
        state_put(20) |> bind
        tell("b") |> bind
        let state=state_get() |> bind
        return state+1
    }
    assert(value.result as ok==21 && value.state==20 && value.log=="ab")
    let failed=computation(StateWriterResultBuilder(10)) {
        state_put(20) |> bind
        tell("a") |> bind
        let missing=result_error("failed",type<int>) |> bind
        after++
        tell("unreachable") |> bind
        return missing
    }
    assert(failed.result is error && failed.result as error=="failed")
    assert(failed.state==10 && failed.log=="a" && after==0)
    let forwarded=computation(StateWriterResultBuilder(10)) {
        tell("outer") |> bind
        return state_writer_result_error("child",type<int>,99,"inner") |> return_from
    }
    assert(forwarded.result is error && forwarded.state==10 && forwarded.log=="outerinner")
    let committed=computation(StateWriterResultBuilder(10)) {
        tell("outer") |> bind
        return state_writer_result_ok(42,99,"inner") |> return_from
    }
    assert(committed.result as ok==42 && committed.state==99 && committed.log=="outerinner")
    let raw=computation(StateWriterResultBuilder(10)) {
        state_put(20) |> bind
        tell("raw") |> bind
        return result_error("raw error",type<int>) |> return_from
    }
    assert(raw.result is error && raw.state==10 && raw.log=="raw")
}
def child(initial:int; fail:bool) {
    return computation(StateWriterResultBuilder(initial)) {
        state_put(initial+5) |> bind
        tell("child;") |> bind
        if (fail) {result_error("child",type<CeUnit>) |> bind}
        return 7
    }
}
def nested() {
    for (fail in fixed_array(false,true)) {
        let value=computation(StateWriterResultBuilder(10)) {
            tell("parent;") |> bind
            state_put(20) |> bind
            let current=state_get() |> bind
            let payload=child(current,fail) |> bind
            let updated=state_get() |> bind
            assert(updated==25 && payload==7)
            tell("after;") |> bind
            return payload
        }
        assert((value.result is error)==fail && value.state==(fail ? 10 : 25))
        assert(value.log==(fail ? "parent;child;" : "parent;child;after;"))
    }
    let later=computation(StateWriterResultBuilder(10)) {
        child(20,false) |> bind
        result_error("later",type<CeUnit>) |> bind
    }
    assert(later.result is error && later.state==10 && later.log=="child;")
}
def loops(failAt:int; useWhile:bool) {
    var visits=0
    let value=computation(StateWriterResultBuilder(10)) {
        tell("start;") |> bind
        if (useWhile) {
            while (visits<3) {
                let current=state_get() |> bind
                state_put(current+1) |> bind
                tell("{visits};") |> bind
                visits++
                if (visits-1==failAt) {result_error("loop",type<CeUnit>) |> bind}
            }
        } else {
            for (i in range(3)) {
                let current=state_get() |> bind
                state_put(current+1) |> bind
                tell("{i};") |> bind
                visits++
                if (i==failAt) {result_error("loop",type<CeUnit>) |> bind}
            }
        }
        tell("end;") |> bind
        return 42
    }
    var expected="start;"
    for (i in range(failAt<0 ? 3 : failAt+1)) {expected+="{i};"}
    if (failAt<0) {expected+="end;"}
    assert(value.log==expected && value.state==(failAt<0 ? 13 : 10))
    assert((value.result is error)==(failAt>=0) && visits==(failAt<0 ? 3 : failAt+1))
}
def zip_loop() {
    let value=computation(StateWriterResultBuilder(10)) {
        for (a,b in range(3),range(4)) {
            let state=state_get() |> bind
            state_put(state+a+b) |> bind
            tell("{a}{b};") |> bind
            if (a==1) {result_error("zip",type<CeUnit>) |> bind}
        }
        after++
        return 42
    }
    assert(value.result is error && value.state==10 && value.log=="00;11;" && after==0)
}
def resources() {
    let before=closed
    let failed=computation(StateWriterResultBuilder(10)) {
        let resource=Resource() |> use_resource
        tell("open;") |> bind
        state_put(20) |> bind
        result_error("stop",type<CeUnit>) |> bind
    }
    assert(failed.result is error && failed.state==10 && failed.log=="open;" && closed==before+1)
    var caught=false
    try {
        let thrown=computation(StateWriterResultBuilder(10)) {
            let resource=Resource() |> use_resource
            tell("open;") |> bind
            panic("native panic")
            return 1
        }
    } recover {caught=true}
    assert(caught && closed==before+2)
}
def make_task() {
    return <- deferred(StateWriterResultBuilder(10),2) $(amount) {
        runs++
        let current=state_get() |> bind
        state_put(current+amount) |> bind
        tell("run;") |> bind
        return current
    }
}
def deferred_runs() {
    let baseline=heap_bytes_allocated()
    {
        let before=runs
        var inscope task <- make_task()
        assert(runs==before)
        let a=run_deferred(task)
        let b=run_deferred(task)
        assert(a.result as ok==10 && b.result as ok==10 && a.state==12 && b.state==12)
        assert(a.log=="run;" && b.log=="run;" && runs==before+2)
    }
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
[export]
def main() {
    basics()
    nested()
    for (failAt in range(-1,3)) {loops(failAt,false); loops(failAt,true)}
    zip_loop()
    resources()
    deferred_runs()
    print("state/writer/result checks OK\n")
}
