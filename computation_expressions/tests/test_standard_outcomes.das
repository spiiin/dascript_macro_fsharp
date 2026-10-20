options gen2
options max_infer_passes=1024
options stack=524288
require daslib/result
require daslib/option
require ../lib/computation.das
require ../lib/task_builder.das
require ../lib/async_sequence_builder.das
require daslib/rtti
var steps=0
struct Settings {n:int}

def checks() {
    verify(default<$Result<int;string>> is err)
    verify(default<$Option<int>> is none)
    let success=computation(ResultBuilder()) {
        let n=ok(20,type<string>) |> bind
        return n+22
    }
    verify(result::is_ok(success) && result::unwrap(success)==42)
    let failed=computation(ResultBuilder()) {
        let n=err("offline",type<int>) |> bind
        steps++
        return n
    }
    verify(result::is_err(failed) && failed as err=="offline" && steps==0)
    let present=computation(OptionBuilder()) {
        let n=option::some(40) |> bind
        return n+2
    }
    verify(option::is_some(present) && option::unwrap(present)==42)
    let absent=computation(OptionBuilder()) {
        let n=option::none(type<int>) |> bind
        steps++
        return n
    }
    verify(option::is_none(absent) && steps==0)
    let grouped=computation(ResultBuilder()) {
        let p=ok(1,type<string>) |> and_bind(ok(Settings(n=2),type<string>)) |> and_bind(ok(3,type<string>)) |> bind
        return p.first.first+p.first.second.n+p.second
    }
    verify(result::unwrap(grouped)==6)
    let groupedOption=computation(OptionBuilder()) {
        let p=some(1) |> and_bind(some(Settings(n=2))) |> and_bind(some(3)) |> bind
        return p.first.first+p.first.second.n+p.second
    }
    verify(option::unwrap(groupedOption)==6)
    verify(result::unwrap(result_ok(7))==7)
    verify(result::is_err(result_error("failure",type<int>)))
    // Explicit standard move constructors interoperate with owned CE and empty
    // their original payload. The owned continuation moves its result again.
    {
        var inscope items <- [1,2]
        var inscope wrapped <- result::move_ok(items,type<string>)
        verify(empty(items))
        var inscope result <- computation(MoveResultBuilder()) {
            var data & = wrapped |> bind
            data |> push(3)
            return <- data
        }
        verify(wrapped is err && result is ok && length(result as ok)==3)
    }
    {
        var inscope items <- [4,5]
        var inscope wrapped <- option::move_some(items)
        verify(empty(items))
        var inscope result <- computation(MoveOptionBuilder()) {
            var data & = wrapped |> bind
            return <- data
        }
        verify(wrapped is none && result is some && length(result as some)==2)
    }
    {
        var inscope result <- computation(MoveOptionBuilder()) {
            var p & = move_some([1]) |> and_bind(move_some([2])) |> and_bind(move_some([3])) |> bind
            return <- p
        }
        verify((result as some).first.first[0]==1 && (result as some).first.second[0]==2 && (result as some).second[0]==3)
    }
    {
        var inscope task <- computation(TaskResultBuilder(type<int>)) {
            let n=task_after_polls(0,ok(41,type<string>)) |> bind
            return n+1
        }
        task_poll(task)
        verify(task.status==TaskStatus.Succeeded && result::unwrap(task.value)==42)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(3)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Standard outcome interoperability checks OK\n")
}
