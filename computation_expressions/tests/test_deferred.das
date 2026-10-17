options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
require ../support/report_builder.das
var steps=0
var acquired=0
var closed=0
var factories=0
struct Resource {}
def acquire() { acquired++; return Resource() }
def ce_dispose(var resource:Resource) { closed++ }
def source() { factories++; return [10,20,30] }
def make_task() {
    var inscope initial <- source()
    return <- deferred(ResultBuilder(),initial) $(snapshot) {
        let resource=acquire() |> use_resource
        steps++
        let x=result_ok(snapshot[0]+snapshot[1]+snapshot[2]) |> bind
        snapshot[0]=999
        return x
    }
}
[export]
def main() {
    let baseline=heap_bytes_allocated()
    for (round in range(12)) {
        {
            var inscope unused <- make_task()
            assert(steps==round*2 && acquired==round*2)
        }
        {
            var inscope task <- make_task()
            let a=run_deferred(task)
            let b=task |> run_deferred
            assert(a as ok==60 && b as ok==60)
        }
        let after=heap_bytes_allocated()
        assert(after==baseline)
    }
    assert(steps==24 && acquired==24 && closed==24 && factories==24)
    {
        var inscope initial <- [2,3]
        var inscope task <- deferred(ListBuilder(),initial) $(snapshot) {
            let x=snapshot |> bind
            let y=[10,20] |> bind
            return x+y
        }
        initial[0]=900
        delete initial
        var inscope first <- run_deferred(task)
        var inscope second <- run_deferred(task)
        delete task
        assert(length(first)==4 && first[0]==12 && first[3]==23 && second[0]==12)
        first[0]=999
        assert(second[0]==12)
    }
    {
        var inscope task <- deferred(ResultBuilder()) { steps++; return 42 }
        var inscope moved <- task
        let result=run_deferred(moved)
        assert(result as ok==42 && steps==25)
        var caught=false
        try { let ignored=run_deferred(task) } recover { caught=true }
        assert(caught)
    }
    for (round in range(10)) {
        {
            var inscope task <- deferred(ResultBuilder(),source()) $(snapshot) {
                let resource=acquire() |> use_resource
                steps++
                snapshot[0]=999
                panic("deferred failure")
                return snapshot[0]
            }
            for (attempt in range(3)) {
                var caught=false
                try { let ignored=run_deferred(task) } recover { caught=true }
                assert(caught)
            }
        }
        let after=heap_bytes_allocated()
        assert(after==baseline)
    }
    assert(closed==54 && acquired==54 && steps==55)
    {
        var inscope task <- deferred(OptionBuilder(),7) $(number) {
            let n=none(type<int>) |> bind
            steps++
            return number+n
        }
        let a=run_deferred(task)
        let b=run_deferred(task)
        assert(a is none && b is none && steps==55)
    }
    {
        var inscope task <- deferred(ResultBuilder(),7) $(number) {
            let n=result_error("not available",type<int>) |> bind
            steps++
            return number+n
        }
        let a=run_deferred(task)
        let b=run_deferred(task)
        assert(a is error && b is error && a as error=="not available" && steps==55)
    }
    {
        var inscope task <- deferred(ReportBuilder(title="Reward"),5) $(number) {
            let p=result_ok(number) |> and_bind(result_ok(2)) |> bind
            return p.first+p.second
        }
        let a=run_deferred(task)
        let b=run_deferred(task)
        assert(a is completed && (a as completed).value==7 && (b as completed).value==7)
    }
    let after=heap_bytes_allocated()
    assert(after==baseline)
    print("deferred behavior and lifetime checks OK\n")
}
