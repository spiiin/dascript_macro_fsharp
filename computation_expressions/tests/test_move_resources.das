options gen2
require ../support/move_resource_support.das
require ../lib/deferred_computation.das
require daslib/rtti
require daslib/strings_boost

def eager() {
    let baseline=heap_bytes_allocated()
    {
        var inscope source <- acquire_buffer(1)
        let result=computation(ResultBuilder()) {
            var buffer & = source |> use_resource
            buffer.data |> push(99)
            return length(buffer.data)
        }
        assert(result as ok==4 && source.id==0 && length(source.data)==0)
        let none=computation(OptionBuilder()) {
            var buffer & = acquire_buffer(2) |> use_resource
            default<$Option<int>> |> bind
            assert(false)
            return 1
        }
        assert(none is none)
        var inscope error <- computation(MoveResultBuilder()) {
            var buffer & = acquire_buffer(3) |> use_resource
            move_error("stop",type<CeUnit>) |> bind
            assert(false)
            return <- buffer.data
        }
        assert(error is err)
        var inscope absent <- computation(MoveOptionBuilder()) {
            var buffer & = acquire_buffer(4) |> use_resource
            move_none(type<CeUnit>) |> bind
            return <- buffer.data
        }
        assert(absent is none)
        var inscope list <- computation(ListBuilder(type<array<int>>)) {
            let id=[5,6] |> bind
            var buffer & = acquire_buffer(id) |> use_resource
            return <- buffer.data
        }
        assert(length(list)==2 && list[0][0]==5 && list[1][0]==6)
    }
    var caught=false
    close_order=""
    try {
        let result=computation(ResultBuilder()) {
            var a & = acquire_buffer(7) |> use_resource
            var b & = acquire_buffer(8) |> use_resource
            panic("body failed")
            return 0
        }
    } recover {caught=true;assert(starts_with(this_context().last_exception,"body failed"))}
    assert(caught && close_order=="87")
    caught=false
    try {
        let result=computation(ResultBuilder()) {
            var a & = acquire_buffer(9) |> use_resource
            var b & = failed_buffer() |> use_resource
            return 0
        }
    } recover {caught=true}
    assert(caught && resources_opened==resources_closed)
    let current=heap_bytes_allocated();assert(current==baseline)
}
def make_stream(fail:bool=false) {
    return <- computation(SequenceBuilder()) {
        var a & = acquire_buffer(1) |> use_resource
        var b & = acquire_buffer(2) |> use_resource
        try_finally($ {
            a.data[0]=10
            yield a.data[0]+b.data[0]
            if(fail) {panic("sequence body failed")}
            yield a.data[1]
        }, $ {assert(a.id==1 && a.data[0]==10 && b.id==2)})
    }
}
def sequences() {
    let baseline=heap_bytes_allocated()
    {
        let opened=resources_opened
        var inscope unstarted <- make_stream()
        sequence_close(unstarted)
        assert(resources_opened==opened)
    }
    close_order=""
    {
        var inscope stream <- make_stream()
        var count=0
        for(value in stream) {count++}
        assert(count==2 && close_order=="21" && resources_opened==resources_closed)
    }
    close_order=""
    {
        var inscope stream <- make_stream()
        for(value in stream) {assert(value==12);break}
        assert(close_order=="21" && resources_opened==resources_closed)
    }
    for(producer in fixed_array(true,false)) {
        var caught=false
        {
            var inscope stream <- make_stream(producer)
            try {sequence_each(stream) $(value:int) {if(!producer) {panic("consumer failed")}}} recover {caught=true}
        }
        assert(caught && resources_opened==resources_closed)
    }
    {
        var inscope stream <- computation(SequenceBuilder()) {
            var a & = acquire_buffer(3) |> use_resource
            var b & = failed_buffer() |> use_resource
            yield 0
        }
        var caught=false
        try {sequence_each(stream) $(value:int) {assert(false)}} recover {caught=true}
        assert(caught && resources_opened==resources_closed)
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}
def deferred_resources() {
    let baseline=heap_bytes_allocated()
    {
        var inscope task <- deferred(SequenceBuilder(type<array<int>>),[4,5]) $(snapshot) {
            var buffer & = acquire_buffer(snapshot[0]) |> use_resource
            yield <- buffer.data
            yield <- [snapshot[1]]
        }
        var inscope a <- run_deferred(task)
        var inscope b <- run_deferred(task)
        delete task
        var inscope kept:array<int>
        for(value in a) {kept <- value;break}
        assert(kept[0]==4)
        var count=0
        sequence_each(b) $(value:array<int>) {count++}
        assert(count==2 && kept[2]==30 && resources_opened==resources_closed)
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}

struct FailingCleanup {data:array<int>}
var cleanup_attempts=0
def failing_cleanup_resource() {var r:FailingCleanup;r.data <- [1,2];return <- r}
def ce_dispose(var r:FailingCleanup) {cleanup_attempts++;delete r;panic("cleanup failed after release")}
def eager_cleanup_failure() {
    let baseline=heap_bytes_allocated()
    let previous=cleanup_attempts
    var caught=false
    try {
        var inscope result <- computation(MoveResultBuilder()) {
            var resource & = failing_cleanup_resource() |> use_resource
            return <- [resource.data[0],99]
        }
    } recover {caught=true}
    assert(caught && cleanup_attempts==previous+1)
    let current=heap_bytes_allocated();assert(current==baseline)
}

[export]
def main() {
    for(round in range(5)) {eager();sequences();deferred_resources();eager_cleanup_failure()}
    print("move-only resource checks OK\n")
}
