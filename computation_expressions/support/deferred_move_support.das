options gen2
module deferred_move_support public
require move_collection_support public
require ../lib/deferred_computation.das public
var snapshot_freed=0
var lazy_steps=0
var cleanup_count=0
struct LootSnapshot {
    values:array<Loot>
    marker:int
    fail:bool
    def finalize {
        if(marker==17) {snapshot_freed++;marker=0}
        delete values
    }
}
def make_loot_snapshot(fail:bool=false) {
    var inscope data:LootSnapshot
    data.values <- loot_list()
    data.marker=17
    data.fail=fail
    return <- data
}
def deferred_loot_list(fail:bool=false) {
    var inscope data <- make_loot_snapshot(fail)
    return <- deferred(ListBuilder(type<Loot>),data) $(snapshot) {
        var value & = snapshot.values |> bind
        if(snapshot.fail && value.items[0]==20) {panic("deferred list failed")}
        value.items |> push(100)
        return <- value
    }
}
def deferred_loot_sequence(fail:bool=false) {
    var inscope data <- make_loot_snapshot(fail)
    return <- deferred(SequenceBuilder(type<Loot>),data) $(snapshot) {
        let feed=open_loot_feed() |> use_resource
        try_finally($ {
            for(i in range(length(snapshot.values))) {
                if(snapshot.fail && i==1) {panic("deferred loot producer failed")}
                lazy_steps++
                snapshot.values[i].items |> push(200)
                yield <- snapshot.values[i]
            }
        }, $ {
            // This callback runs before the run snapshot is destroyed.
            assert(snapshot.marker==17 && length(snapshot.values)==3)
            cleanup_count++
        })
    }
}
