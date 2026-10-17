options gen2
require ../lib/computation.das
require ../lib/validation_builder.das

def price(name:string) { return name=="Sword" ? result_ok(30) : result_error("Unknown item",type<int>) }
[export]
def main() {
    let purchase=computation(ResultBuilder()) {
        let p=result_ok("Sword") |> and_bind(result_ok(50)) |> bind
        let cost=price(p.first) |> bind
        if (p.second<cost) { return result_error("Not enough gold",type<int>) |> return_from }
        else { return p.second-cost }
    }
    assert(purchase is ok && purchase as ok==20)
    var inscope loadouts <- computation(ListBuilder()) {
        let p=[10,20] |> and_bind([1,2]) |> bind
        let score=p.first+p.second
        let bonus=[0,100] |> bind
        return score+bonus
    }
    assert(length(loadouts)==8 && loadouts[0]==11 && loadouts[7]==122)
    print("bind2 demo OK\n")
}
