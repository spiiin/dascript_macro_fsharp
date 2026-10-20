options gen2
require ./game_model.das
require daslib/rtti
[export]
def main() {
    var inscope before <- example_player()
    var inscope after <- example_player()
    assert(derive_equal(before,after))
    assert(derive_hash(before)==derive_hash(after))
    after.stats.health-=25
    assert(!derive_equal(before,after))
    assert(before.stats.health==100)
    print("{derive_debug(before)}\n")
    print("{derive_debug(after)}\n")
    print("Derive game demo OK\n")
}
