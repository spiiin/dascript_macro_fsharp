options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
require daslib/rtti
require daslib/strings_boost
var opened=fixed_array(0,0,0)
var closed=fixed_array(0,0,0)
var pulled=fixed_array(0,0,0)
var bodies=0
var after=0
struct Resource {id:int}
def acquire(id:int) {opened[id]++; return Resource(id=id)}
def ce_dispose(var resource:Resource) {closed[resource.id]++}
def stream(id,failAt:int) {
    return <- computation(SequenceBuilder()) {
        let resource=acquire(id) |> use_resource
        for (i in range(5)) {
            if (i==failAt) {panic("producer {id}")}
            pulled[id]++
            yield i
        }
    }
}
def reset() {
    for (v in opened) {v=0}
    for (v in closed) {v=0}
    for (v in pulled) {v=0}
    bodies=0; after=0
}
def producer(failing,at:int) {
    reset()
    let before=heap_bytes_allocated()
    var caught=false
    try {
        let result=computation(ResultBuilder()) {
            for (a in stream(failing,at)) {
                variant type<$Result<int;string>>(ok=a) |> bind
                bodies++
            }
            after++
        }
    } recover {
        caught=true
        assert(starts_with(this_context().last_exception,"producer {failing}"))
    }
    assert(caught && bodies==at && after==0)
    for (a,b in opened,closed) {assert(a==b)}
    let current=heap_bytes_allocated()
    assert(before==current)
}
def consumer() {
    reset()
    let before=heap_bytes_allocated()
    var caught=false
    try {
        var inscope a <- stream(0,-1)
        let result=computation(OptionBuilder()) {
            for (x in a) {
                let value=variant type<$Option<int>>(some=x) |> bind
                bodies++
                if (x==2) {panic("consumer")}
            }
            after++
        }
    } recover {
        caught=true
        assert(starts_with(this_context().last_exception,"consumer"))
    }
    assert(caught && bodies==3 && after==0)
    assert(opened[0]==1 && closed[0]==1 && pulled[0]==3)
    let current=heap_bytes_allocated()
    assert(before==current)
}
def array_failure() {
    var inscope values <- [1,2,3]
    var caught=false
    try {
        let result=computation(ResultBuilder()) {
            for (value in values) {
                value+=10
                if (value==12) {panic("array body")}
            }
        }
    } recover {caught=true; assert(starts_with(this_context().last_exception,"array body"))}
    assert(caught && values[0]==11 && values[1]==12 && values[2]==3)
    values |> push(4)
    assert(length(values)==4)
}
def temporary() {return <- [1,2,3]}
def temporary_failure() {
    let before=heap_bytes_allocated()
    var caught=false
    try {
        let result=computation(ResultBuilder()) {
            for (a in temporary()) {panic("temporary body")}
        }
    } recover {caught=true; assert(starts_with(this_context().last_exception,"temporary body"))}
    assert(caught)
    let current=heap_bytes_allocated()
    assert(before==current)
}
def broken_source() : iterator<int> {
    panic("source construction")
    var result:iterator<int>
    return <- result
}
def construction_failure() {
    let before=heap_bytes_allocated()
    var caught=false
    try {
        let result=computation(ResultBuilder()) {
            for (a in broken_source()) {bodies++}
        }
    } recover {caught=true; assert(starts_with(this_context().last_exception,"source construction"))}
    assert(caught)
    let current=heap_bytes_allocated()
    assert(before==current)
}
def deferred_failure() {
    var inscope task <- deferred(OptionBuilder(),[10,20,30]) $(data) {
        for (item in stream(0,-1)) {
            data[0]++
            assert(data[0]==11)
            panic("deferred body")
        }
    }
    let before=heap_bytes_allocated()
    for (round in range(5)) {
        reset()
        var caught=false
        try {let result=run_deferred(task)} recover {
            caught=true
            assert(starts_with(this_context().last_exception,"deferred body"))
        }
        assert(caught && opened[0]==1 && closed[0]==1)
        let current=heap_bytes_allocated()
        assert(before==current)
    }
}

def stop_step(builder:ResultBuilder; value:int) {
    return value==2 ? result_error("stop",type<int>) : result_ok(value)
}
def stop_step(builder:OptionBuilder; value:int) {
    return value==2 ? none(type<int>) : some(value)
}
def early_stop(builder:auto) {
    reset()
    let baseline=heap_bytes_allocated()
    let result=computation(builder) {
        for (value in stream(0,-1)) {
            stop_step(builder,value) |> bind
            bodies++
        }
        after++
    }
    assert(opened[0]==1 && closed[0]==1 && pulled[0]==3 && bodies==2 && after==0)
    let current=heap_bytes_allocated()
    assert(baseline==current)
}

// A reference cursor must release each(array)'s lock and retain mutations.
def reference_failure() {
    let baseline=heap_bytes_allocated()
    {
        var inscope values <- [1,2,3]
        var caught=false
        unsafe {
            var inscope source <- each(values)
            try {
                let result=computation(OptionBuilder()) {
                    for (value in source) {
                        value+=10
                        some(value) |> bind
                        if (value==12) {panic("reference body")}
                    }
                }
            } recover {caught=true; assert(starts_with(this_context().last_exception,"reference body"))}
            // Closing a consumed source again is safe.
            sequence_close(source)
        }
        assert(caught && values[0]==11 && values[1]==12 && values[2]==3)
        values |> push(4)
    }
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
struct Record {a:int; b:int; c:int; d:int; e:int; f:int}
def record_stream() {
    return <- computation(SequenceBuilder(type<Record>)) {
        yield Record(a=10,f=60)
        yield Record(a=20,f=70)
    }
}
def value_records() {
    let baseline=heap_bytes_allocated()
    var count=0
    let result=computation(ResultBuilder()) {
        for (record in record_stream()) {
            assert(record.a==(count==0 ? 10 : 20))
            assert(record.f==(count==0 ? 60 : 70))
            count++
        }
    }
    assert(result is ok && count==2)
    let current=heap_bytes_allocated()
    assert(baseline==current)
}

[export]
def main() {
    for (round in range(5)) {
        for (which in range(3)) {producer(which,0); producer(which,2)}
        consumer()
        reference_failure()
        value_records()
        early_stop(ResultBuilder())
        early_stop(OptionBuilder())
        array_failure()
        temporary_failure()
        construction_failure()
    }
    deferred_failure()
    // CE recovery observes the original message after all source finalizers ran.
    reset()
    let recovered=computation(ResultBuilder()) {
        try_with($ {
            for (a in stream(0,-1)) {panic("recover me")}
        }, $(message:string) {
            assert(starts_with(message,"recover me"))
            assert(closed[0]==1)
        })
        return 42
    }
    assert(recovered as ok==42)
    print("single For exception cleanup checks OK\n")
}
