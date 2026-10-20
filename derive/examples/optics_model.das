options gen2
module optics_model public
require ../lib/derive.das public
[derive(clone=true)]
struct OpticStats {health:int=100;bonuses:array<int>}
variant OpticAction {idle;stats:OpticStats;items:array<int>}
[derive(clone=true)]
struct OpticPlayer {
    name:string
    stats:OpticStats=OpticStats()
    inventory:array<int>
    optional:$Option<OpticStats>
    field:$JsonField<OpticStats>
    action:OpticAction=OpticAction(idle)
    fixed:int[2]=fixed_array(4,5)
}
def optics_player() : OpticPlayer {
    var result=OpticPlayer(name="Alice")
    result.stats.bonuses <- [2,3];result.inventory <- [1,2,3]
    return <- result
}
