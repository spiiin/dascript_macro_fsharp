options gen2
require ../lib/computation_macro.das
require ../support/bounded_result_builder.das

[export]
def main() {
    var inscope enemies <- [100,200,300]
    var inscope damage <- [10,20]
    var hits=0
    let battle=computation(ResultBuilder()) {
        for (hp,hit in enemies,damage) {
            let amount=variant<ok:int;error:string>(ok=hit) |> bind
            hp-=amount
            hits++
        }
        return hits
    }
    assert(battle is ok && battle as ok==2)
    assert(enemies[0]==90 && enemies[1]==180 && enemies[2]==300)

    var turns=0
    let limited=computation(BoundedResultBuilder(limit=2)) {
        for (x,y,z in range(5),range(6),range(7)) {
            variant<ok:int;error:string>(ok=x+y+z) |> bind
            turns++
        }
        return turns
    }
    assert(limited is error && limited as error=="zip for budget exhausted" && turns==2)
    print("zip for demo OK\n")
}
