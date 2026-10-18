options gen2
require ../lib/computation_macro.das
require ../lib/query_builder.das
struct Player {name:string;team:string;score:int}
[export]
def main() {
    let players=fixed_array(Player(name="Alice",team="red",score=90),Player(name="Bob",team="blue",score=30),Player(name="Cara",team="red",score=90),Player(name="Dan",team="blue",score=75))
    var inscope ranking <- players |> query_order_by(true) <| $(p:Player) {return p.score}
    assert(ranking[0].name=="Alice" && ranking[1].name=="Cara")
    for(p in ranking) {print("{p.name}: {p.score}\n")}
    // distinct keeps the first row per key: after ranking, the best of each team.
    var inscope champions <- ranking |> query_distinct <| $(p:Player) {return p.team}
    assert(length(champions)==2 && champions[0].name=="Alice" && champions[1].name=="Dan")
    var inscope report <- computation(QueryBuilder(type<string>)) {
        var group & = players |> query_group_by <| $(p:Player) {return p.team} |> bind
        var total=0
        for(p in group.values) {total+=p.score}
        return "{group.key}: {length(group.values)} players, score={total}"
    }
    assert(length(report)==2 && report[0]=="red: 2 players, score=180" && report[1]=="blue: 2 players, score=105")
    for(line in report) {print("{line}\n")}
    var inscope teams <- fixed_array("red","blue","red") |> query_distinct()
    assert(length(teams)==2 && teams[0]=="red" && teams[1]=="blue")
    print("Query operators demo OK\n")
}
