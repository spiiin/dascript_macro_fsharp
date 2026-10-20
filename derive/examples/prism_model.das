options gen2
module prism_model public
require ./optics_model.das public

def prism_player() : OpticPlayer {
    var result <- optics_player()
    result.optional <- move_some(derive_clone(result.stats))
    result.field <- json_move_present(derive_clone(result.stats))
    result.action <- OpticAction(stats <- derive_clone(result.stats))
    return <- result
}
// Nested partial paths exercise short-circuit guards before every cast.
[derive(clone=true)]
struct PrismNest {player:$Option<OpticPlayer>;side:array<int>}
def prism_nest() : PrismNest {
    var result:PrismNest
    result.player <- move_some(prism_player())
    result.side <- [8,9]
    return <- result
}
