options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
var steps=0

def rewards() {
    var inscope amounts <- [10,20,30]
    return <- deferred(SequenceBuilder(),amounts) $(snapshot) {
        for (index in range(length(snapshot))) {
            steps++
            snapshot[index]+=1
            yield snapshot[index]
        }
    }
}
[export]
def main() {
    var inscope task <- rewards()
    var inscope first <- run_deferred(task)
    var inscope second <- task |> run_deferred
    delete task
    assert(steps==0)
    var a=0
    var b=0
    verify(next(first,a))
    verify(next(second,b))
    assert(a==11 && b==11)
    sequence_close(first)
    var total=b
    for(value in second) { total+=value }
    assert(total==63 && steps==4)
    print("deferred sequence demo OK\n")
}
