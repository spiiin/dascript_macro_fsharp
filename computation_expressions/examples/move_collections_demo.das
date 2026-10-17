options gen2
require ../support/move_collection_support.das
[export]
def main() {
    var inscope rewards <- computation(ListBuilder(type<Loot>)) {
        var reward & = loot_list() |> bind
        reward.items |> push(100)
        return <- reward
    }
    assert(length(rewards)==3 && rewards[0].items[1]==100)
    var inscope selected:Loot
    {
        var inscope stream <- computation(SequenceBuilder(type<Loot>)) {
            var reward & = loot_sequence() |> bind
            reward.items |> push(200)
            yield <- reward
        }
        for(reward in stream) {
            selected <- reward
            break
        }
    }
    assert(selected.items[0]==10 && selected.items[1]==200)
    assert(feeds_opened==feeds_closed)
    print("move-only collections demo OK\n")
}
