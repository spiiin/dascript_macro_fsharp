options gen2
require ../support/deferred_move_support.das
[export]
def main() {
    var inscope listTask <- deferred_loot_list()
    var inscope first <- run_deferred(listTask)
    var inscope second <- listTask |> run_deferred
    first[0].items[0]=999
    assert(second[0].items[0]==10)

    var inscope streamTask <- deferred_loot_sequence()
    var inscope a <- run_deferred(streamTask)
    var inscope b <- run_deferred(streamTask)
    delete streamTask // each run already owns a separate snapshot
    var inscope selected:Loot
    for(reward in a) {selected <- reward;break}
    assert(selected.items[0]==10 && selected.items[1]==200)
    var count=0
    sequence_each(b) $(reward:Loot) {count++;assert(length(reward.items)==2)}
    assert(count==3 && feeds_opened==feeds_closed)
    print("deferred move-only collections demo OK\n")
}
