options gen2
require ../lib/computation.das
require ../support/bounded_result_builder.das
require ../lib/deferred_computation.das
require daslib/rtti
require math

var order=""
var attempts=0
var completed=0
var after=0
var pulled=fixed_array(0,0,0)
var closed=fixed_array(0,0,0)

def source(id:int; count:int) {order+="{id}"; return range(count)}
def step(builder:ResultBuilder; i,failAt:int) {
    attempts++
    if (i==failAt) {return variant<ok:int;error:string>(error="stop {i}")}
    return variant<ok:int;error:string>(ok=i)
}
def step(builder:OptionBuilder; i,failAt:int) {
    attempts++
    if (i==failAt) {return variant<some:int;none:bool>(none=true)}
    return variant<some:int;none:bool>(some=i)
}
def failed(value:variant<ok:auto;error:string>) {return value is error}
def failed(value:variant<some:auto;none:bool>) {return value is none}
def reset() {
    order=""; attempts=0; completed=0; after=0
    for (v in pulled) {v=0}
    for (v in closed) {v=0}
}
def check_lengths(builder:auto; a,b,c,failAt:int) {
    reset()
    let shortest=min(a,min(b,c))
    let fails=failAt>=0 && failAt<shortest
    let result=computation(builder) {
        for (x,y,z in source(1,a),source(2,b),source(3,c)) {
            assert(x==y && y==z)
            let value=step(builder,x,failAt) |> bind
            assert(value==x)
            completed++
        }
        after++
        return completed
    }
    assert(order=="123")
    assert(failed(result)==fails)
    assert(attempts==(fails ? failAt+1 : shortest))
    assert(completed==(fails ? failAt : shortest) && after==(fails ? 0 : 1))
}

def stream(id,count:int) {
    return <- computation(SequenceBuilder()) {
        try_finally($ {
            for (i in range(count)) {pulled[id]++; yield i}
        }, $ {closed[id]++})
    }
}
def iterator_failure(builder:auto) {
    reset()
    let before=heap_bytes_allocated()
    {
        var inscope a <- stream(0,20)
        var inscope b <- stream(1,30)
        var inscope c <- stream(2,40)
        let result=computation(builder) {
            for (x,y,z in a,b,c) {
                step(builder,x,2) |> bind
                completed++
            }
            after++
            return 99
        }
        assert(failed(result) && attempts==3 && completed==2 && after==0)
        assert(pulled[0]==3 && pulled[1]==3 && pulled[2]==3)
        assert(closed[0]==1 && closed[1]==1 && closed[2]==1)
    }
    let current=heap_bytes_allocated()
    assert(before==current)
}

def references(builder:auto) {
    reset()
    var inscope hp <- [100,200,300,400]
    let damage=fixed_array(10,20,30)
    let result=computation(builder) {
        for (health,amount,index in hp,damage,range(4)) {
            step(builder,index,1) |> bind
            health-=amount
        }
    }
    assert(failed(result) && hp[0]==90 && hp[1]==200 && hp[2]==300 && attempts==2)
    // All native array locks must have been released on the failed iteration.
    hp |> push(500)
    assert(length(hp)==5)
}

def temporaries() {return <- [1,2,3]}
def temporary_lifetime(builder:auto) {
    let before=heap_bytes_allocated()
    for (round in range(10)) {
        let result=computation(builder) {
            for (a,b in temporaries(),temporaries()) {step(builder,a,1) |> bind}
        }
        assert(failed(result))
    }
    let current=heap_bytes_allocated()
    assert(before==current)
}

def skipped_and_nested(builder:auto) {
    reset()
    let skipped=computation(builder) {
        step(builder,0,0) |> bind
        for (x,y in source(1,3),source(2,4)) {completed++}
        return 42
    }
    assert(failed(skipped) && order=="" && completed==0)
    reset()
    let nested=computation(builder) {
        for (outer,other in range(3),range(4)) {
            for (x,y in source(1,5),source(2,5)) {
                step(builder,x,1) |> bind
                completed++
            }
            after++
        }
    }
    assert(failed(nested) && order=="12" && completed==1 && attempts==2 && after==0)
}

def native_shortest(builder:auto) {
    // Preserve native next() timing even when one producer finishes first.
    reset()
    {
        var inscope a <- stream(0,4)
        var inscope b <- stream(1,2)
        var inscope c <- stream(2,5)
        for (x,y,z in a,b,c) {completed++}
    }
    let expected=fixed_array(pulled[0],pulled[1],pulled[2])
    assert(completed==2 && closed[0]==1 && closed[1]==1 && closed[2]==1)
    reset()
    {
        var inscope a <- stream(0,4)
        var inscope b <- stream(1,2)
        var inscope c <- stream(2,5)
        let result=computation(builder) {for (x,y,z in a,b,c) {completed++}}
        assert(!failed(result))
    }
    assert(completed==2 && closed[0]==1 && closed[1]==1 && closed[2]==1)
    assert(pulled[0]==expected[0] && pulled[1]==expected[1] && pulled[2]==expected[2])
}

def all_checks(builder:auto) {
    for (a in range(4)) {
        for (b in range(4)) {
            for (c in range(4)) {
                for (failure in range(-1,4)) {check_lengths(builder,a,b,c,failure)}
            }
        }
    }
    iterator_failure(builder)
    references(builder)
    temporary_lifetime(builder)
    skipped_and_nested(builder)
    native_shortest(builder)
}
[export]
def main() {
    all_checks(ResultBuilder()); all_checks(OptionBuilder())
    reset()
    let bounded=computation(BoundedResultBuilder(limit=2)) {
        for (a,b,c,d in range(5),range(6),range(7),range(8)) {
            variant<ok:int;error:string>(ok=a+b+c+d) |> bind
            completed++
        }
        after++
        return completed
    }
    assert(bounded is error && bounded as error=="zip for budget exhausted" && completed==2 && after==0)
    reset()
    var inscope task <- deferred(ResultBuilder(),[10,20,30]) $(data) {
        for (a,b in data,range(2)) {completed+=a+b}
        return completed
    }
    assert(completed==0)
    let first=run_deferred(task)
    let second=run_deferred(task)
    assert(first as ok==31 && second as ok==62)
    print("zip for checks OK\n")
}
