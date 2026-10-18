options gen2
require ../lib/computation_macro.das
require ../lib/query_builder.das
require daslib/rtti
var effects=""
var released=0
struct Resource {id:int}
def ce_dispose(var r:Resource) {released++}
def check() {
    effects=""
    var inscope rows <- computation(QueryBuilder()) {
        let n=fixed_array(1,2,3) |> bind
        effects+="{n}"
        query_where(n!=2) |> bind
        effects+="!"
        return n*10
    }
    assert(effects=="1!23!" && length(rows)==2 && rows[0]==10 && rows[1]==30)
    var inscope join <- query_join(fixed_array(1,2,1),fixed_array(1,1,3),$(x:int){return x},$(x:int){return x})
    assert(length(join)==4)
    for(row in join) {assert(row.first==1 && row.second==1)}
    var leftKeys=0
    var rightKeys=0
    var inscope keyed <- query_join(fixed_array(1,2),fixed_array(2,1,2),
        $(n:int){leftKeys++;return n},$(n:int){rightKeys++;return n})
    assert(leftKeys==2 && rightKeys==6 && length(keyed)==3 && keyed[0].first==1 && keyed[1].first==2)
    var inscope emptyRows:array<int>
    var inscope emptyJoin <- query_join(emptyRows,fixed_array(1),$(x:int){return x},$(x:int){return x})
    assert(length(emptyJoin)==0)
    var inscope filtered <- fixed_array(1,2,3) |> query_where <| $(x:int){return x>1}
    var inscope selected <- filtered |> query_select <| $(x:int){return "n={x}"}
    assert(length(selected)==2 && selected[0]=="n=2" && selected[1]=="n=3")
    // The block-last syntax also composes with CE bind.
    var inscope pipeRows <- computation(QueryBuilder()) {
        let n=fixed_array(1,2,3) |> query_where <| $(x:int) {return x>1} |> bind
        let scaled=fixed_array(n) |> query_select <| $(x:int) {return x*10} |> bind
        return scaled
    }
    assert(length(pipeRows)==2 && pipeRows[0]==20 && pipeRows[1]==30)
    // Keep coverage of the original call form as well.
    var inscope oldFilter <- query_where(fixed_array(1,2,3),$(x:int){return x>1})
    var inscope oldSelect <- query_select(oldFilter,$(x:int){return "n={x}"})
    assert(length(oldSelect)==length(selected) && oldSelect[0]==selected[0] && oldSelect[1]==selected[1])

    var inscope grouped <- computation(QueryBuilder()) {
        let pair=fixed_array(1,2) |> and_bind(fixed_array(10,20)) |> bind
        return pair.first+pair.second
    }
    assert(length(grouped)==4 && grouped[0]==11 && grouped[1]==21 && grouped[2]==12 && grouped[3]==22)
    var inscope loop <- computation(QueryBuilder()) {
        for(i in range(3)) {if(i!=1) {yield i}}
    }
    assert(length(loop)==2 && loop[0]==0 && loop[1]==2)
    var failedProject=false
    try {
        var inscope badProjection <- fixed_array(1,2) |> query_select <| $(n:int){if(n==2){panic("projection")};return n}
    } recover {failedProject=true}
    assert(failedProject)
    var failedPredicate=false
    try {
        var inscope badFilter <- fixed_array(1,2) |> query_where <| $(n:int){if(n==2){panic("predicate")};return true}
    } recover {failedPredicate=true}
    assert(failedPredicate)
    var failedKey=false
    try {
        var inscope badJoin <- query_join(fixed_array(1,2),fixed_array(1,2),
            $(n:int){return n},$(n:int){if(n==2){panic("key")};return n})
    } recover {failedKey=true}
    assert(failedKey)
    let before=released
    var caught=false
    try {
        var inscope bad <- computation(QueryBuilder()) {
            let resource=Resource(id=1) |> use_resource
            let n=fixed_array(1,2) |> bind
            if(n==2) {panic("query failure")}
            return n
        }
    } recover {caught=true}
    assert(caught && released==before+1)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Query checks OK\n")
}
