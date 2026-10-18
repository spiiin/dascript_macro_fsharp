options gen2
require ../lib/computation_macro.das
require ../lib/query_builder.das
require daslib/rtti
struct Row {id:int;team:string;score:int}
var calls=""
def check() {
    let source=fixed_array(Row(id=1,team="red",score=20),Row(id=2,team="blue",score=30),Row(id=3,team="red",score=30),Row(id=4,team="blue",score=10),Row(id=5,team="green",score=20))
    calls=""
    var inscope sorted <- source |> query_order_by($(row:Row) {calls+="{row.id}";return row.score})
    verify(calls=="12345" && length(sorted)==5)
    verify(sorted[0].id==4 && sorted[1].id==1 && sorted[2].id==5 && sorted[3].id==2 && sorted[4].id==3)
    var inscope descending <- source |> query_order_by($(row:Row) {return row.score},true)
    verify(descending[0].id==2 && descending[1].id==3 && descending[2].id==1 && descending[3].id==5 && descending[4].id==4)
    calls=""
    var inscope pipeDescending <- source |> query_order_by(true) <| $(row:Row) {calls+="{row.id}";return row.score}
    verify(calls=="12345")
    var inscope pipeAscending <- source |> query_order_by(false) <| $(row:Row) {return row.score}
    var inscope directDescending <- query_order_by(source,true,$(row:Row) {return row.score})
    for(i in range(length(source))) {
        verify(pipeDescending[i].id==descending[i].id && directDescending[i].id==descending[i].id)
        verify(pipeAscending[i].id==sorted[i].id)
    }
    verify(source[0].id==1 && source[4].id==5)
    calls=""
    var inscope groups <- source |> query_group_by <| $(row:Row) {calls+="{row.id}";return row.team}
    verify(calls=="12345" && length(groups)==3)
    verify(groups[0].key=="red" && groups[1].key=="blue" && groups[2].key=="green")
    verify(length(groups[0].values)==2 && groups[0].values[0].id==1 && groups[0].values[1].id==3)
    verify(length(groups[1].values)==2 && groups[1].values[0].id==2 && groups[1].values[1].id==4)
    verify(length(groups[2].values)==1 && groups[2].values[0].id==5)
    groups[0].values[0].score=999
    verify(source[0].score==20)
    calls=""
    var inscope distinct <- source |> query_distinct <| $(row:Row) {calls+="{row.id}";return row.team}
    verify(calls=="12345" && length(distinct)==3 && distinct[0].id==1 && distinct[1].id==2 && distinct[2].id==5)
    var inscope oldGroups <- query_group_by(source,$(row:Row) {return row.team})
    var inscope oldDistinct <- query_distinct(source,$(row:Row) {return row.team})
    verify(length(oldGroups)==length(groups) && length(oldDistinct)==length(distinct))
    for(i in range(length(groups))) {
        verify(oldGroups[i].key==groups[i].key && length(oldGroups[i].values)==length(groups[i].values))
        verify(oldDistinct[i].id==distinct[i].id)
    }

    var inscope numbers <- fixed_array(3,1,3,2,1) |> query_distinct()
    verify(length(numbers)==3 && numbers[0]==3 && numbers[1]==1 && numbers[2]==2)
    var inscope words <- fixed_array("b","a","b") |> query_distinct()
    var inscope alphabetical <- words |> query_order_by($(word:string) {return word})
    verify(length(alphabetical)==2 && alphabetical[0]=="a" && alphabetical[1]=="b")
    var inscope same <- fixed_array(3,1,2) |> query_order_by($(n:int) {return 0})
    verify(same[0]==3 && same[1]==1 && same[2]==2)
    // Use each operator as a source in the ordinary CE protocol.
    var inscope report <- computation(QueryBuilder(type<string>)) {
        var group & =source |> query_group_by <| $(row:Row) {return row.team} |> bind
        return "{group.key}:{length(group.values)}"
    }
    verify(length(report)==3 && report[0]=="red:2" && report[2]=="green:1")
    var inscope best <- computation(QueryBuilder()) {
        let row=source |> query_order_by(true) <| $(row:Row) {return row.score} |> bind
        query_where(row.score>=20) |> bind
        return row.id
    }
    verify(length(best)==4 && best[0]==2 && best[1]==3 && best[2]==1 && best[3]==5)
    var inscope teams <- computation(QueryBuilder()) {
        let row=source |> query_distinct <| $(row:Row) {return row.team} |> bind
        return row.id
    }
    verify(length(teams)==3 && teams[2]==5)
    // Dynamic inputs stay borrowed, including empty collections.
    var inscope dynamic <- source |> query_select <| $(row:Row) {return row.score}
    var inscope dynamicSorted <- dynamic |> query_order_by($(n:int) {return n})
    var inscope dynamicGroups <- dynamic |> query_group_by <| $(n:int) {return n}
    var inscope dynamicDistinct <- dynamic |> query_distinct()
    verify(length(dynamic)==5 && dynamic[0]==20 && dynamicSorted[0]==10 && length(dynamicGroups)==3 && length(dynamicDistinct)==3)
    var inscope empty:array<int>
    var emptyCalls=0
    var inscope emptyOrder <- empty |> query_order_by($(n:int) {emptyCalls++;return n})
    var inscope emptyGroups <- empty |> query_group_by <| $(n:int) {emptyCalls++;return n}
    var inscope emptyDistinct <- empty |> query_distinct <| $(n:int) {emptyCalls++;return n}
    verify(emptyCalls==0 && length(emptyOrder)==0 && length(emptyGroups)==0 && length(emptyDistinct)==0)
    var inscope one <- fixed_array(7) |> query_order_by($(n:int) {return n})
    verify(length(one)==1 && one[0]==7)
    // Sort larger, uneven merge runs, ascending/descending and stable ties.
    var inscope many:array<Row>
    for(i in range(137)) {many |> push(Row(id=i,score=(i*31)%11))}
    var inscope asc <- many |> query_order_by($(row:Row) {return row.score})
    var inscope desc <- many |> query_order_by($(row:Row) {return row.score},true)
    for(i in range(1,length(many))) {
        verify(asc[i-1].score<=asc[i].score && desc[i-1].score>=desc[i].score)
        if(asc[i-1].score==asc[i].score) {verify(asc[i-1].id<asc[i].id)}
        if(desc[i-1].score==desc[i].score) {verify(desc[i-1].id<desc[i].id)}
    }
    // Owning group sources are released if a continuation throws.
    var groupFailed=false
    try {
        var inscope badReport <- computation(QueryBuilder(type<string>)) {
            var group & = source |> query_group_by <| $(row:Row) {return row.team} |> bind
            if(group.key=="blue") {panic("group continuation")}
            return group.key
        }
    } recover {groupFailed=true}
    verify(groupFailed)
    // All callbacks can throw after partial accumulation, without leaking.
    var caught=false
    var attempts=0
    try {
        var inscope bad <- source |> query_order_by(true) <| $(row:Row) {attempts++;if(row.id==3) {panic("order key")};return row.score}
    } recover {caught=true}
    verify(caught && attempts==3 && source[0].score==20)
    caught=false;attempts=0
    try {
        var inscope bad <- source |> query_group_by <| $(row:Row) {attempts++;if(row.id==4) {panic("group key")};return row.team}
    } recover {caught=true}
    verify(caught && attempts==4)
    caught=false;attempts=0
    try {
        var inscope bad <- source |> query_distinct <| $(row:Row) {attempts++;if(row.id==4) {panic("distinct key")};return row.team}
    } recover {caught=true}
    verify(caught && attempts==4)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Query operators checks OK\n")
}
