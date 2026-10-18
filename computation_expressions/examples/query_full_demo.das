options gen2
require ../lib/computation_macro.das
require ../lib/query_builder.das
require daslib/rtti

struct Player {name:string;team:string;score:int;active:bool}
struct ScoreRow {name:string;team:string;score:int}

def query_full_report() {
    let players=fixed_array(
        Player(name="Alice",team="red",score=90,active=true),
        Player(name="Bob",team="blue",score=30,active=true),
        Player(name="Cara",team="red",score=75,active=true),
        Player(name="Dan",team="blue",score=75,active=true),
        Player(name="Alice",team="red",score=90,active=true),
        Player(name="Eve",team="blue",score=100,active=false)
    )
    // Each collection operation borrows its input; scope every owning result.
    var inscope filtered <- players |> query_where <| $(p:Player) {return p.active && p.score>=50}
    assert(length(filtered)==4)

    var inscope scores <- filtered |> query_select <| $(p:Player) {
            return ScoreRow(name=p.name,team=p.team,score=p.score)
        }
    assert(length(scores)==4)

    // true = descending; equal scores retain their source order.
    var inscope ranking <- scores |> query_order_by(true) <| $(row:ScoreRow) {return row.score}
    assert(ranking[0].name=="Alice" && ranking[1].name=="Alice")
    assert(ranking[2].name=="Cara" && ranking[3].name=="Dan")

    var inscope unique <- ranking |> query_distinct <| $(row:ScoreRow) {return row.name}
    assert(length(unique)==3 && unique[0].name=="Alice" && unique[1].name=="Cara" && unique[2].name=="Dan")

    var inscope report <- computation(QueryBuilder(type<string>)) {
        // Groups own nested arrays; this bind consumes and scopes their owner.
        var group & = unique |> query_group_by <| $(row:ScoreRow) {return row.team} |> bind
        var total=0
        for(player in group.values) {total+=player.score}
        return "{group.key}: players={length(group.values)}, score={total}"
    }
    return <- report
}

def check_query_full_report(show:bool=false) {
    // Report remains valid after all intermediate arrays in query_full_report close.
    var inscope report <- query_full_report()
    assert(length(report)==2)
    assert(report[0]=="red: players=2, score=165")
    assert(report[1]=="blue: players=1, score=75")
    if(show) {for(line in report) {print("{line}\n")}}
}

[export]
def main() {
    check_query_full_report(true)
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {
        check_query_full_report()
        verify(heap_bytes_allocated()==baseline)
    }
    print("Query full demo OK\n")
}
