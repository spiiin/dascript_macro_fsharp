options gen2
require ../support/move_collection_support.das
[export]
def main() {
 var inscope values <- computation(ListBuilder(type<Loot>)) {
    var pair & = loot_list() |> and_bind(loot_list()) |> bind
    return <- pair.first
 }
}
