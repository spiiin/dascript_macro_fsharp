options gen2
require ../lib/computation_macro.das
require ../lib/search_builder.das
def solutions() {
    return <- computation(SearchBuilder(type<string>)) {
        let sword=fixed_array(2,4,6) |> bind
        let armor=fixed_array(1,3) |> bind
        search_guard(sword+armor==7) |> bind
        yield "sword={sword}, armor={armor}"
    }
}
[export]
def main() {
    var inscope all <- solutions()
    var count=0
    sequence_each(all) $(value:string) {print("{value}\n");count++}
    assert(count==2)
    var inscope first <- search_cut(solutions())
    count=0
    sequence_each(first) $(value:string) {print("first: {value}\n");count++}
    assert(count==1)
    print("Search demo OK\n")
}
