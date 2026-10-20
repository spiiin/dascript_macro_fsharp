options gen2
require ../lib/computation.das
require ../support/bounded_result_builder.das
require ../lib/deferred_computation.das
require daslib/rtti

var sources=0
var conditions=0
var attempted=0
var completed=0
var after=0
var releases=0

def source() { sources++; return range(5) }
def condition(n:int) { conditions++; return n<5 }
def step(builder:ResultBuilder; i:int) {
    attempted++
    if (i==2) { return variant type<$Result<int;string>>(err="stop") }
    return variant type<$Result<int;string>>(ok=i)
}
def step(builder:OptionBuilder; i:int) {
    attempted++
    if (i==2) { return default<$Option<int>> }
    return variant type<$Option<int>>(some=i)
}
def failed(value:$Result<auto;string>) { return value is err }
def failed(value:$Option<auto>) { return value is none }
def reset() { sources=0; conditions=0; attempted=0; completed=0; after=0 }

def stops(builder:auto) {
    reset()
    let a=computation(builder) {
        for (i in source()) {
            let n=step(builder,i) |> bind
            completed++
        }
        after++
        return 42
    }
    assert(failed(a) && sources==1 && attempted==3 && completed==2 && after==0)
    reset()
    var n=0
    let b=computation(builder) {
        while (condition(n)) {
            step(builder,n) |> bind
            n++
        }
        after++
        return 42
    }
    assert(failed(b) && n==2 && conditions==3 && attempted==3 && after==0)
    reset()
    let c=computation(builder) {
        for (i in range(3)) {
            var j=0
            while (condition(j)) { step(builder,j) |> bind; j++ }
            completed++
        }
        after++
        return 42
    }
    assert(failed(c) && conditions==3 && attempted==3 && completed==0 && after==0)
}

def arrays(builder:auto) {
    var inscope values <- [0,1,2,3,4]
    reset()
    let a=computation(builder) {
        for (v in values) {
            step(builder,v) |> bind
            v+=10
        }
    }
    assert(failed(a) && values[0]==10 && values[1]==11 && values[2]==2 && attempted==3)
    // Borrowed arrays remain usable and mutable after early exit.
    values |> push(5)
    var fixed=fixed_array(1,2)
    let b=computation(builder) { for (v in fixed) { v+=1 } }
    assert(!failed(b) && fixed[0]==2 && fixed[1]==3)
    let constant=fixed_array(4,5)
    var sum=0
    let c=computation(builder) { for (v in constant) {sum+=v} }
    assert(!failed(c) && sum==9)
}

def iterators(builder:auto) {
    releases=0
    reset()
    var inscope stream <- computation(SequenceBuilder()) {
        try_finally($ { for (i in range(5)) {yield i} }, $ {releases++})
    }
    let r=computation(builder) {
        for (i in stream) { step(builder,i) |> bind; completed++ }
    }
    assert(failed(r) && attempted==3 && completed==2 && releases==1)
    var inscope values <- [1,2,3]
    unsafe {
        var inscope refs <- each(values)
        let changed=computation(builder) { for (v in refs) {v+=10} }
        assert(!failed(changed) && values[0]==11 && values[2]==13)
    }
}

def array_lock_cleanup() {
    var inscope values <- [1,2,3]
    var caught=false
    try {
        let result=computation(ResultBuilder()) {
            for (v in values) { values |> push(9); v+=1 }
        }
    } recover { caught=true }
    assert(caught && length(values)==3)
    // Reallocation is forbidden during traversal, but the error releases the lock.
    values |> push(4)
    assert(length(values)==4)
}

def temporary() { return <- [1,2,3] }
def temporary_lifetime() {
    let before=heap_bytes_allocated()
    for (round in range(10)) {
        let r=computation(ResultBuilder()) {
            for (v in temporary()) { variant type<$Result<int;string>>(err="stop") |> bind }
        }
        assert(r is err)
    }
    let afterBytes=heap_bytes_allocated()
    assert(before==afterBytes)
}

[export]
def main() {
    stops(ResultBuilder()); stops(OptionBuilder())
    arrays(ResultBuilder()); arrays(OptionBuilder())
    iterators(ResultBuilder()); iterators(OptionBuilder())
    array_lock_cleanup()
    temporary_lifetime()
    reset()
    let limited=computation(BoundedResultBuilder(limit=2)) {
        for (i in source()) { completed++ }
        after++
        return 9
    }
    assert(limited is err && limited as err=="for budget exhausted")
    assert(sources==1 && completed==2 && after==0)
    reset()
    var n=0
    let bounded=computation(BoundedResultBuilder(limit=2)) {
        while (condition(n)) { n++ }
        after++
        return n
    }
    assert(bounded is err && n==2 && conditions==3 && after==0)
    // User errors win over budget errors and do not evaluate another guard.
    reset()
    let userError=computation(BoundedResultBuilder(limit=10)) {
        while (condition(0)) { variant type<$Result<int;string>>(err="user") |> bind }
    }
    assert(userError is err && userError as err=="user" && conditions==1)
    let empty=computation(BoundedResultBuilder(limit=0)) {
        for (i in range(0)) { panic("unreachable") }
        while (false) { panic("unreachable") }
        return 7
    }
    assert(empty is ok && empty as ok==7)
    // Runtime hooks remain deferred and execute again on every run.
    var inscope task <- deferred(BoundedResultBuilder(limit=2)) {
        for (i in range(5)) { completed++ }
    }
    completed=0
    let first=run_deferred(task)
    let second=run_deferred(task)
    assert(first is err && second is err && completed==4)
    print("loop protocol checks OK\n")
}
