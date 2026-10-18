options gen2
require ../lib/computation_macro.das
require ../lib/search_builder.das
require daslib/rtti
var steps=0
var acquired=0
var released=0
var closeOrder=0
struct Resource {id:int}
def ce_dispose(var resource:Resource) {released++;closeOrder=closeOrder*10+resource.id}
def choices(id:int; failAt:int=0) {
    return <- computation(SearchBuilder()) {
        let resource=Resource(id=id) |> use_resource
        acquired++
        let n=search_choose([1,2,3]) |> bind
        steps++
        if(n==failAt) {panic("alternative failed")}
        yield id*10+n
    }
}
def reset() {steps=0;acquired=0;released=0;closeOrder=0}
def check() {
    reset()
    var inscope limited <- choices(1) |> search_take(2)
    var value=0
    verify(ce_sequence_next_value(limited,value) && value==11 && released==0)
    verify(ce_sequence_next_value(limited,value) && value==12)
    verify(steps==2 && acquired==1 && released==1)
    verify(!ce_sequence_next_value(limited,value))
    sequence_close(limited)
    verify(released==1)

    reset()
    for(limit in fixed_array(0,-3)) {
        var inscope empty <- choices(1) |> search_take(limit)
        verify(!ce_sequence_next_value(empty,value))
        sequence_close(empty)
    }
    verify(steps==0 && acquired==0 && released==0)
    var inscope started <- choices(1)
    verify(ce_sequence_next_value(started,value))
    var inscope stop <- started |> search_take(0)
    verify(!ce_sequence_next_value(stop,value) && released==1 && steps==1)

    reset()
    var inscope longLimit <- choices(1) |> search_take(99)
    var count=0
    sequence_each(longLimit) $(n:int) {count++}
    verify(count==3 && steps==3 && released==1)
    var emptyValues:array<int>
    var inscope emptySource <- search_choose(emptyValues) |> search_take(2)
    verify(!ce_sequence_next_value(emptySource,value))

    reset()
    var inscope alternatives <- choices(1) |> search_append(choices(2))
    verify(acquired==0)
    verify(ce_sequence_next_value(alternatives,value) && value==11 && acquired==1)
    verify(ce_sequence_next_value(alternatives,value) && value==12)
    verify(ce_sequence_next_value(alternatives,value) && value==13 && released==0)
    verify(ce_sequence_next_value(alternatives,value) && value==21)
    verify(acquired==2 && released==1 && closeOrder==1)
    sequence_close(alternatives)
    verify(released==2 && closeOrder==12)

    reset()
    var inscope both <- computation(SearchBuilder()) {
        let n=choices(1) |> search_append(choices(2)) |> search_take(4) |> bind
        yield n+100
    }
    var inscope results:array<int>
    sequence_each(both) $(n:int) {results |> push(n)}
    verify(length(results)==4 && results[0]==111 && results[1]==112 && results[2]==113 && results[3]==121)
    verify(steps==4 && released==2 && closeOrder==12)

    // Already active right is also owned; breaking left closes both.
    reset()
    var inscope right <- choices(2)
    verify(ce_sequence_next_value(right,value))
    var inscope early <- choices(1) |> search_append(right) |> search_take(10)
    for(n in early) {verify(n==11);break}
    verify(released==2 && closeOrder==12)
    sequence_close(early)
    verify(released==2 && closeOrder==12 && steps==2)

    reset()
    var inscope badRight <- choices(2)
    verify(ce_sequence_next_value(badRight,value))
    var inscope bad <- choices(1,2) |> search_append(badRight) |> search_take(8)
    var caught=false
    try {sequence_each(bad) $(n:int) {}} recover {caught=true}
    verify(caught && released==2 && closeOrder==12)
    sequence_close(bad)
    verify(released==2)

    reset()
    var inscope badSecond <- choices(1) |> search_append(choices(2,2))
    caught=false
    try {sequence_each(badSecond) $(n:int) {}} recover {caught=true}
    verify(caught && released==2 && closeOrder==12)

    reset()
    var inscope consumerRight <- choices(2)
    verify(ce_sequence_next_value(consumerRight,value))
    var inscope consumer <- choices(1) |> search_append(consumerRight) |> search_take(6)
    caught=false
    try {sequence_each(consumer) $(n:int) {panic("consumer failed")}} recover {caught=true}
    verify(caught && released==2 && closeOrder==12)

    // Closing before first step must free captured arrays without running bodies.
    reset()
    var inscope unopened <- search_choose([1,2,3]) |> search_append(search_choose([4,5,6])) |> search_take(4)
    sequence_close(unopened)
    var inscope unused <- choices(1) |> search_append(choices(2))
    sequence_close(unused)
    verify(acquired==0 && released==0)

    // Empty alternatives, duplicate solutions, associativity, scoped cut.
    var emptyAlternative:array<int>
    var inscope merged <- search_choose(emptyAlternative) |> search_append(search_choose([1,1])) |> search_append(search_choose([2]))
    var inscope nested <- search_choose([1]) |> search_append(search_choose([1]) |> search_append(search_choose([2])))
    var inscope a:array<int>
    var inscope b:array<int>
    sequence_each(merged) $(n:int) {a |> push(n)}
    sequence_each(nested) $(n:int) {b |> push(n)}
    verify(length(a)==3 && length(b)==3)
    for(i in range(3)) {verify(a[i]==b[i])}
    verify(a[0]==1 && a[1]==1 && a[2]==2)
    reset()
    var inscope cut <- search_cut(choices(1) |> search_append(choices(2)))
    sequence_each(cut) $(n:int) {verify(n==11 && released==1)}
    verify(steps==1 && acquired==1 && released==1)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Search combinators checks OK\n")
}
