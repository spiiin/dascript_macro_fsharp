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
            for (a,b,c in stream(0,failing==0 ? at : -1),stream(1,failing==1 ? at : -1),stream(2,failing==2 ? at : -1)) {
                variant<ok:int;error:string>(ok=a+b+c) |> bind
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
        var inscope b <- stream(1,-1)
        var inscope c <- stream(2,-1)
        let result=computation(OptionBuilder()) {
            for (x,y,z in a,b,c) {
                let value=variant<some:int;none:bool>(some=x+y+z) |> bind
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
    for (a,b,c in opened,closed,pulled) {assert(a==1 && b==1 && c==3)}
    let current=heap_bytes_allocated()
    assert(before==current)
}
def array_failure() {
    var inscope values <- [1,2,3]
    var caught=false
    try {
        let result=computation(ResultBuilder()) {
            for (value,i in values,range(3)) {
                value+=10
                if (i==1) {panic("array body")}
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
            for (a,b,c in temporary(),temporary(),temporary()) {panic("temporary body")}
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
            for (a,b,c in stream(0,-1),broken_source(),stream(2,-1)) {bodies++}
        }
    } recover {caught=true; assert(starts_with(this_context().last_exception,"source construction"))}
    assert(caught)
    let current=heap_bytes_allocated()
    assert(before==current)
}
def deferred_failure() {
    var inscope task <- deferred(OptionBuilder(),[10,20,30]) $(data) {
        for (value,item in data,stream(0,-1)) {
            value++
            assert(value==11)
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

[export]
def main() {
    for (round in range(5)) {
        for (which in range(3)) {producer(which,0); producer(which,2)}
        consumer()
        array_failure()
        temporary_failure()
        construction_failure()
    }
    deferred_failure()
    // CE recovery observes the original message after all source finalizers ran.
    reset()
    let recovered=computation(ResultBuilder()) {
        try_with($ {
            for (a,b in stream(0,-1),stream(1,-1)) {panic("recover me")}
        }, $(message:string) {
            assert(starts_with(message,"recover me"))
            assert(closed[0]==1 && closed[1]==1)
        })
        return 42
    }
    assert(recovered as ok==42)
    print("zip exception cleanup checks OK\n")
}
