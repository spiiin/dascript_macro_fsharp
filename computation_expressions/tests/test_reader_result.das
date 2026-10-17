options gen2
require ../lib/computation.das
require ../lib/reader_result_builder.das
require ../lib/deferred_computation.das
require daslib/rtti

struct Rules { limit:int=2; multiplier:int=3 }
var reached=0
var closed=0
var opened=0
var runs=0
struct Resource {}
def acquire() {opened++; return Resource()}
def ce_dispose(var resource:Resource) {closed++}
def allowed(value,limit:int) {
    if (value>=limit) {return result_error("limit",type<CeUnit>)}
    return result_ok(CeUnit())
}
def feed(fail:bool) {
    return <- computation(SequenceBuilder()) {
        let resource=acquire() |> use_resource
        for (i in range(5)) {
            if (fail && i==1) {panic("producer")}
            yield i
        }
    }
}
def basics() {
    var rules=Rules()
    let builder=ReaderResultBuilder(rules)
    rules.multiplier=99
    let mapped=computation(ReaderResultBuilder(builder.environment)) {
        let config=reader_ask() |> bind
        return config.multiplier
    }
    assert(mapped as ok==3)
    let skipped=computation(ReaderResultBuilder(builder.environment)) {
        let missing=result_error("missing",type<int>) |> bind
        reached++
        let config=reader_ask() |> bind
        return missing*config.multiplier
    }
    assert(skipped is error && skipped as error=="missing" && reached==0)
    let optimized=computation(ReaderResultBuilder(builder.environment)) {
        let missing=result_error("map",type<int>) |> bind
        return missing+1
    }
    assert(optimized is error && optimized as error=="map")
    let empty=computation(ReaderResultBuilder(builder.environment)) { }
    assert(empty is ok)
    let forwarded=computation(ReaderResultBuilder(builder.environment)) {
        return result_error("forwarded",type<int>) |> return_from
    }
    assert(forwarded is error && forwarded as error=="forwarded")
    let branch=computation(ReaderResultBuilder(builder.environment)) {
        if (true) {result_error("branch",type<CeUnit>) |> bind}
        reached++
        return 1
    }
    assert(branch is error && reached==0)
    let paired=computation(ReaderResultBuilder(builder.environment)) {
        let pair=reader_ask() |> and_bind(result_ok(4)) |> bind
        return pair.first.multiplier*pair.second
    }
    assert(paired as ok==12)
    let triple=computation(ReaderResultBuilder(builder.environment)) {
        let pair=result_ok(4) |> and_bind(reader_ask()) |> and_bind(result_ok(5)) |> bind
        return pair.first.first+pair.first.second.multiplier+pair.second
    }
    assert(triple as ok==12)
    let failedPair=computation(ReaderResultBuilder(builder.environment)) {
        let pair=result_error("left",type<int>) |> and_bind(result_error("right",type<int>)) |> bind
        reached++
        return pair.first+pair.second
    }
    assert(failedPair is error && failedPair as error=="left" && reached==0)
    let rightFailure=computation(ReaderResultBuilder(builder.environment)) {
        let pair=reader_ask() |> and_bind(result_error("right",type<int>)) |> bind
        return pair.first.multiplier+pair.second
    }
    assert(rightFailure is error && rightFailure as error=="right")
}
def loops() {
    let builder=ReaderResultBuilder(Rules())
    var visits=0
    let failed=computation(ReaderResultBuilder(builder.environment)) {
        for (i in range(5)) {
            let config=reader_ask() |> bind
            visits++
            allowed(i,config.limit) |> bind
            reached++
        }
        reached+=100
        return 1
    }
    assert(failed is error && visits==3 && reached==2)
    reached=0
    visits=0
    let failedWhile=computation(ReaderResultBuilder(builder.environment)) {
        while (visits<5) {
            let config=reader_ask() |> bind
            visits++
            allowed(visits,config.limit) |> bind
        }
        reached++
        return 1
    }
    assert(failedWhile is error && visits==2 && reached==0)
    visits=0
    let zipped=computation(ReaderResultBuilder(builder.environment)) {
        for (a,b in range(5),range(5)) {
            visits++
            allowed(a+b,2) |> bind
        }
        reached++
        return 1
    }
    assert(zipped is error && visits==2 && reached==0)
    let complete=computation(ReaderResultBuilder(builder.environment)) {
        for (i in range(2)) {allowed(i,3) |> bind}
        return 42
    }
    assert(complete as ok==42)
}
def resources() {
    let baseline=heap_bytes_allocated()
    let builder=ReaderResultBuilder(Rules())
    let failed=computation(ReaderResultBuilder(builder.environment)) {
        let resource=acquire() |> use_resource
        result_error("resource",type<CeUnit>) |> bind
        reached++
        return 1
    }
    assert(failed is error && opened==closed && reached==0)
    let stopped=computation(ReaderResultBuilder(builder.environment)) {
        for (i in feed(false)) {allowed(i,1) |> bind}
        reached++
        return 1
    }
    assert(stopped is error && opened==closed && reached==0)
    let completed=computation(ReaderResultBuilder(builder.environment)) {
        let resource=acquire() |> use_resource
        for (i in feed(false)) {result_ok(CeUnit()) |> bind}
        return 42
    }
    assert(completed as ok==42 && opened==closed)
    for (producer in fixed_array(false,true)) {
        var caught=false
        try {
            let outcome=computation(ReaderResultBuilder(builder.environment)) {
                let resource=acquire() |> use_resource
                for (i in feed(producer)) {
                    if (!producer) {panic("consumer")}
                    result_ok(CeUnit()) |> bind
                }
                return 1
            }
        } recover {caught=true}
        assert(caught && opened==closed)
    }
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
def task_factory() {
    var rules=Rules()
    var inscope task <- deferred(ReaderResultBuilder(rules),7) $(snapshot) {
        runs++
        let config=reader_ask() |> bind
        let value=result_ok(snapshot) |> bind
        return value*config.multiplier
    }
    rules.multiplier=99
    return <- task
}
def deferred_runs() {
    let baseline=heap_bytes_allocated()
    {
        var inscope task <- task_factory()
        let before=runs
        let first=run_deferred(task)
        let second=run_deferred(task)
        assert(first as ok==21 && second as ok==21 && runs==before+2)
    }
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
[export]
def main() {
    for (round in range(3)) {
        basics()
        loops()
        resources()
        deferred_runs()
    }
    print("reader/result checks OK\n")
}


