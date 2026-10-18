options gen2
require ../lib/computation_macro.das
require ../lib/search_builder.das
var opened=0
var closed=0
struct SearchResource {name:string}
def ce_dispose(var resource:SearchResource) {closed++;print("close {resource.name}\n")}
def equipment(name:string; offset:int) {
    return <- computation(SearchBuilder(type<string>)) {
        let resource=SearchResource(name=name) |> use_resource
        opened++
        let sword=fixed_array(2,4,6) |> bind
        let armor=fixed_array(1,3) |> bind
        search_guard(sword+armor==7) |> bind
        yield "{name}: sword={sword+offset}, armor={armor}"
    }
}
[export]
def main() {
    // Each search is lazy. Keep two shop solutions, then one warehouse solution.
    var inscope selected <- computation(SearchBuilder(type<string>)) {
        let item=equipment("shop",0) |> search_append(equipment("warehouse",10)) |> search_take(3) |> bind
        yield item
    }
    assert(opened==0 && closed==0)
    var count=0
    sequence_each(selected) $(item:string) {count++;print("{item}\n")}
    assert(count==3 && opened==2 && closed==2)
    // A scoped owner or explicit sequence_close also handles a partial traversal.
    var inscope first <- equipment("early",0) |> search_append(equipment("unused",20))
    for(item in first) {print("first: {item}\n");break}
    sequence_close(first)
    assert(opened==3 && closed==3)
    print("Search alternatives demo OK\n")
}
