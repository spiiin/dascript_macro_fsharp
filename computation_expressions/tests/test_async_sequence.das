options gen2
require ../lib/computation_macro.das
require ../lib/async_sequence_builder.das

var itemFinalized=0
struct CopyItem {value:int
    def finalize {itemFinalized++}
}
def unused_items() {return <- computation(AsyncSequenceBuilder(type<CopyItem>)) {}}

def empty_stream() {return <- computation(AsyncSequenceBuilder()) {}}
def stopped_stream() {
    return <- computation(AsyncSequenceBuilder()) {
        yield 7
        return
        panic("code after return must not run")
    }
}
def loop_stream() {
    return <- computation(AsyncSequenceBuilder()) {
        for(i in range(5)) {
            let n=task_after_polls(0,i) |> bind
            if(n==1) {continue}
            if(n==3) {break}
            yield n
        }
        yield 99
    }
}
def recovered_stream() {
    return <- computation(AsyncSequenceBuilder()) {
        try_with($ {
            task_after_polls(1,CeUnit()) |> bind
            panic("recover producer")
        },$(message:string) {yield 8})
        yield 9
    }
}
[export]
def main() {
    // The type marker must not construct/finalize an extra payload instance.
    let before=itemFinalized
    {var inscope unused <- unused_items()}
    verify(itemFinalized==before)
    var inscope stream <- computation(AsyncSequenceBuilder()) {
        let value=task_after_polls(1,42) |> bind
        yield value
        yield 43
    }
    var inscope first <- async_sequence_next(stream)
    verify(task_poll(first)==TaskStatus.Waiting)
    verify(task_poll(first)==TaskStatus.Succeeded && (task_value(first) as some)==42)
    var inscope second <- async_sequence_next(stream)
    verify(task_poll(second)==TaskStatus.Succeeded && (task_value(second) as some)==43)
    var inscope done <- async_sequence_next(stream)
    verify(task_poll(done)==TaskStatus.Succeeded && (task_value(done) is none))
    var inscope empty <- empty_stream()
    var inscope emptyNext <- async_sequence_next(empty)
    verify(task_poll(emptyNext)==TaskStatus.Succeeded && task_value(emptyNext) is none)
    var inscope stopped <- stopped_stream()
    var inscope beforeReturn <- async_sequence_next(stopped)
    verify(task_poll(beforeReturn)==TaskStatus.Succeeded && task_value(beforeReturn) as some==7)
    var inscope afterReturn <- async_sequence_next(stopped)
    verify(task_poll(afterReturn)==TaskStatus.Succeeded && task_value(afterReturn) is none)
    // Ordinary Option/Result values remain payloads in this builder.
    var inscope strings <- computation(AsyncSequenceBuilder(type<string>)) {
        let text=task_after_polls(0,"hello") |> bind
        yield text
    }
    var inscope text <- async_sequence_next(strings)
    verify(task_poll(text)==TaskStatus.Succeeded && task_value(text) as some=="hello")
    var inscope loop <- loop_stream()
    for(i in range(3)) {
        var inscope item <- async_sequence_next(loop)
        verify(task_poll(item)==TaskStatus.Succeeded)
        verify(task_value(item) as some==(i==0 ? 0 : (i==1 ? 2 : 99)))
    }
    var inscope recovered <- recovered_stream()
    var inscope eight <- async_sequence_next(recovered)
    verify(task_poll(eight)==TaskStatus.Waiting)
    verify(task_poll(eight)==TaskStatus.Succeeded && task_value(eight) as some==8)
    var inscope nine <- async_sequence_next(recovered)
    verify(task_poll(nine)==TaskStatus.Succeeded && task_value(nine) as some==9)
    print("Async sequence checks OK\n")
}
