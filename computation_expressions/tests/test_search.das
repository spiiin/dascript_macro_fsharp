options gen2
require ../lib/computation_macro.das
require ../lib/search_builder.das
require daslib/rtti
var visited=0
var released=0
struct Resource {id:int}
def ce_dispose(var resource:Resource) {released++}
def candidates(fail:bool=false) {
    return <- computation(SearchBuilder()) {
        let resource=Resource(id=1) |> use_resource
        let x=search_choose([1,2,3]) |> bind
        visited++
        if(fail && x==2) {panic("search failure")}
        yield x
    }
}
def check() {
    visited=0;released=0
    var inscope all <- computation(SearchBuilder()) {
        let x=search_choose([1,2,3]) |> bind
        let y=fixed_array(10,20) |> bind
        search_guard(x!=2) |> bind
        yield x+y
    }
    var inscope values:array<int>
    sequence_each(all) $(n:int) {values |> push(n)}
    assert(length(values)==4 && values[0]==11 && values[1]==21 && values[2]==13 && values[3]==23)
    var inscope first <- search_once(candidates())
    assert(visited==0 && released==0)
    sequence_each(first) $(n:int) {assert(n==1)}
    assert(visited==1 && released==1)
    var inscope cut <- computation(SearchBuilder()) {
        let x=fixed_array(10,20) |> bind
        let y=search_cut(candidates()) |> bind
        yield x+y
    }
    var total=0
    sequence_each(cut) $(n:int) {total+=n}
    assert(total==32 && visited==3 && released==3)
    var inscope early <- candidates()
    for(n in early) {assert(n==1);break}
    sequence_close(early)
    assert(released==4)
    var caught=false
    var inscope bad <- candidates(true)
    try {sequence_each(bad) $(n:int) {}} recover {caught=true}
    assert(caught && released==5)
    var inscope consumer <- candidates()
    caught=false
    try {sequence_each(consumer) $(n:int) {panic("consumer")}} recover {caught=true}
    assert(caught && released==6)
    var inscope emptySearch <- computation(SearchBuilder()) {search_guard(false) |> bind;yield 99}
    var inscope noSolution <- search_cut(emptySearch)
    var found=0
    sequence_each(noSolution) $(n:int) {found++}
    assert(found==0)
    var inscope unopened <- search_once(candidates())
    sequence_close(unopened)
    assert(released==6)
    var inscope unusedChoices <- search_choose([1,2,3])
    sequence_close(unusedChoices)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Search checks OK\n")
}
