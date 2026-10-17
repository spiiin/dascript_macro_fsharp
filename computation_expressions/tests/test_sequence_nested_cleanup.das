options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
require daslib/rtti
require daslib/strings_boost
var opened=fixed_array(0,0,0)
var closed=fixed_array(0,0,0)
var reads=0
var after=0
var order=""
struct Resource {id:int}
def acquire(id:int) {opened[id]++; return Resource(id=id)}
def ce_dispose(var r:Resource) {closed[r.id]++; order+="{r.id}"}
def reset() {for(v in opened) {v=0}; for(v in closed) {v=0}; reads=0;after=0;order=""}
def source(failAt:int; id:int=1) {
    return <- computation(SequenceBuilder()) {
        let resource=acquire(id) |> use_resource
        for(i in range(4)) {
            if(i==failAt) {panic("child producer")}
            reads++
            yield i
        }
    }
}
def outer(mode,failAt:int; bodyFail:bool) {
    return <- computation(SequenceBuilder()) {
        let resource=acquire(0) |> use_resource
        if(mode==0) {
            for(value in source(failAt)) {
                if(bodyFail && value==1) {panic("outer body")}
                yield value
            }
        } elif(mode==1) {
            let value=source(failAt) |> bind
            if(bodyFail && value==1) {panic("outer body")}
            yield value
        } else {
            source(failAt) |> yield_from
        }
        after++
    }
}
def check(mode,exitMode:int) {
    reset()
    let baseline=heap_bytes_allocated()
    {
        var inscope stream <- outer(mode,-1,false)
        if(exitMode==0) {
            // Closing an unstarted sequence acquires nothing.
            sequence_close(stream)
        } elif(exitMode==1) {
            var value=-1
            let more=next(stream,value)
            assert(more && value==0)
            assert(opened[0]==1 && opened[1]==1 && closed[0]==0 && closed[1]==0)
            sequence_close(stream)
        } elif(exitMode==2) {
            for(value in stream) {assert(value==0);break}
        } else {
            var count=0
            sequence_each(stream) $(value:int) {assert(value==count);count++}
            assert(count==4)
        }
        sequence_close(stream)
        if(exitMode==0) {assert(order=="" && reads==0)}
        else {assert(order=="10" && closed[0]==1 && closed[1]==1)}
        assert(after==(exitMode==3 ? 1 : 0))
        if(exitMode==1 || exitMode==2) {assert(reads==1)}
    }
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
def failure(mode,failAt:int; bodyFail:bool) {
    reset()
    let baseline=heap_bytes_allocated()
    {
        var inscope stream <- outer(mode,failAt,bodyFail)
        var caught=false
        try {
            var value=0
            while(next(stream,value)) {}
        } recover {
            caught=true
            assert(starts_with(this_context().last_exception,bodyFail ? "outer body" : "child producer"))
            // Cleanup has already happened, before deleting the outer wrapper.
            assert(order=="10" && closed[0]==1 && closed[1]==1)
        }
        assert(caught && after==0)
        sequence_close(stream)
    }
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
var mutableValues:array<int>
def references():iterator<int&> {unsafe {return <- each(mutableValues)}}
def reference_case() {
    let baseline=heap_bytes_allocated()
    mutableValues <- [1,2,3]
    {
        var inscope stream <- computation(SequenceBuilder()) {
            for(value in references()) {value+=10;yield value}
        }
        for(value in stream) {assert(value==11);break}
        mutableValues |> push(4)
        assert(mutableValues[0]==11 && mutableValues[1]==2 && length(mutableValues)==4)
    }
    delete mutableValues
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
def deferred_case() {
    var inscope task <- deferred(SequenceBuilder(),fixed_array(5,6)) $(snapshot) {
        let resource=acquire(0) |> use_resource
        let value=source(-1) |> bind
        yield snapshot[0]+value
    }
    let baseline=heap_bytes_allocated()
    for(round in range(4)) {
        reset()
        {
            var inscope stream <- run_deferred(task)
            for(value in stream) {assert(value==5);break}
            assert(order=="10")
        }
        let current=heap_bytes_allocated()
        assert(baseline==current)
    }
}
// A native producer has no Sequence protection of its own.
def raw_source(failAt,id:int) {
    return <- generator<int> {
        var resource=acquire(id)
        for(i in range(4)) {
            if(i==failAt) {panic("child producer")}
            reads++
            yield i
        }
        return false
    } finally {ce_sequence_finalize($ {ce_dispose(resource)})}
}
def zip_case(failAt:int) {
    reset()
    let baseline=heap_bytes_allocated()
    {
        var inscope stream <- computation(SequenceBuilder()) {
            let resource=acquire(0) |> use_resource
            for(a,b in raw_source(-1,1),raw_source(failAt,2)) {yield a+b}
            after++
        }
        var caught=false
        try {
            if(failAt<0) {for(value in stream) {assert(value==0);break}}
            else {sequence_each(stream) $(value:int) {}}
        } recover {caught=true;assert(starts_with(this_context().last_exception,"child producer"))}
        assert(caught==(failAt>=0) && after==0)
        if(failAt>=0) {assert(starts_with(order,"2"))}
        for(value in closed) {assert(value==1)}
        assert(ends_with(order,"0"))
    }
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
def chained_bind() {
    reset()
    let baseline=heap_bytes_allocated()
    {
        var inscope stream <- computation(SequenceBuilder()) {
            let resource=acquire(0) |> use_resource
            let a=source(-1,1) |> bind
            let b=source(-1,2) |> bind
            yield a+b
        }
        for(value in stream) {assert(value==0);break}
        assert(closed[1]==1 && closed[2]==1 && ends_with(order,"0") && reads==2)
    }
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
def consumer_failure() {
    reset()
    let baseline=heap_bytes_allocated()
    var caught=false
    try {
        var inscope stream <- outer(1,-1,false)
        sequence_each(stream) $(value:int) {panic("outside consumer")}
    } recover {caught=true;assert(starts_with(this_context().last_exception,"outside consumer"))}
    assert(caught && order=="10" && reads==1 && after==0)
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
def temporary() {return <- [1,2,3]}
def broken_source():iterator<int> {
    panic("source construction")
    var result:iterator<int>
    return <- result
}
def setup_failure() {
    reset()
    let baseline=heap_bytes_allocated()
    var caught=false
    try {
        var inscope stream <- computation(SequenceBuilder()) {
            let resource=acquire(0) |> use_resource
            for(a,b in source(-1),broken_source()) {yield a+b}
        }
        sequence_each(stream) $(value:int) {}
    } recover {caught=true;assert(starts_with(this_context().last_exception,"source construction"))}
    assert(caught && opened[0]==closed[0] && opened[1]==closed[1])
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
def temporary_failure() {
    let baseline=heap_bytes_allocated()
    var caught=false
    try {
        var inscope stream <- computation(SequenceBuilder()) {
            let value=temporary() |> bind
            yield value
            panic("temporary body")
        }
        sequence_each(stream) $(value:int) {}
    } recover {caught=true;assert(starts_with(this_context().last_exception,"temporary body"))}
    assert(caught)
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
[export]
def main() {
    for(round in range(4)) {
        for(mode in range(3)) {
            for(exitMode in range(4)) {check(mode,exitMode)}
            failure(mode,0,false)
            failure(mode,2,false)
            if(mode!=2) {failure(mode,-1,true)}
        }
        reference_case()
        zip_case(-1);zip_case(0);zip_case(2)
        chained_bind()
        consumer_failure()
        setup_failure()
        temporary_failure()
    }
    deferred_case()
    print("nested Sequence cleanup checks OK\n")
}
