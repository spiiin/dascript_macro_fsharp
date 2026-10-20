options gen2
require ../examples/game_model.das
require daslib/rtti
def check() {
    var inscope players:array<Player>
    var inscope player <- example_player()
    players |> emplace(player)
    var inscope other:array<Player>
    player <- example_player()
    other |> emplace(player)
    verify(derive_equal(players,other) && derive_hash(players)==derive_hash(other))
    verify(derive_debug(players)=="[Player\{name=\"Alice\", stats=Stats\{health=100, mana=25\}, skills=[\"dash\", \"heal\"]\}]")
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive cross-module checks OK\n")
}
