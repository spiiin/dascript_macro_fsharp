options gen2
require ../support/deferred_move_support.das
[export]
def main() {
    var inscope task <- deferred(SequenceBuilder(type<Loot>),loot_list()) $(snapshot) {
        var reward & = snapshot |> bind
        reward.items |> push(100)
        yield <- reward
    }
    var inscope left <- run_deferred(task)
    var inscope right <- run_deferred(task)
    delete task
    var inscope a:Loot
    var inscope b:Loot
    let gotLeft=sequence_next_move(left,a)
    let gotRight=sequence_next_move(right,b)
    assert(gotLeft && gotRight && a.items[0]==10 && b.items[0]==10)
    sequence_close(left)
    // Each successful pull replaces b, freeing its previous items.
    var count=1
    while(sequence_next_move(right,b)) {count++}
    assert(count==3 && b.items[0]==30 && a.items[1]==100)
    print("sequence_next_move demo OK\n")
}
