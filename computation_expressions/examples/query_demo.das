options gen2
require ../lib/computation_macro.das
require ../lib/query_builder.das
struct Player {name:string; team:int; score:int}
struct Team {id:int; title:string}
[export]
def main() {
    let players=fixed_array(Player(name="Alice",team=1,score=90),Player(name="Bob",team=2,score=30),Player(name="Cara",team=1,score=75))
    let teams=fixed_array(Team(id=1,title="red"),Team(id=2,title="blue"))
    var inscope report <- computation(QueryBuilder(type<string>)) {
        let row=query_join(players,teams,$(p:Player){return p.team},$(t:Team){return t.id}) |> bind
        query_where(row.first.score>=50) |> bind
        return "{row.first.name}: {row.second.title}"
    }
    assert(length(report)==2 && report[0]=="Alice: red" && report[1]=="Cara: red")
    var inscope filtered <- players |> query_where <| $(p:Player){return p.score>=50}
    var inscope scores <- filtered |> query_select <| $(p:Player){return p.score}
    assert(length(scores)==2 && scores[0]==90 && scores[1]==75)
    print("Query demo OK\n")
}
