options gen2
module diff_model public
require ../lib/derive.das public

[derive(diff=true,clone=true)]
struct DiffStats {health:int;mana:int}
[derive(diff=true,clone=true)]
struct DiffItem {id:int;count:int}
variant DiffAction {idle;move:DiffStats;items:array<DiffItem>;note:string}
variant DiffNested {stop;action:DiffAction}
[derive(diff=true,clone=true)]
struct DiffGame {
    title:string
    stats:DiffStats
    items:array<DiffItem>
    removed:array<int>
    fixed:int[2]
    option:$Option<DiffStats>
    patch:$JsonField<DiffStats>
    action:DiffAction
    nested:DiffNested
}
def diff_before() : DiffGame {
    var game:DiffGame
    game.title="Arena"
    game.stats=DiffStats(health=100,mana=20)
    game.items |> push(DiffItem(id=1,count=3))
    game.removed <- [7,8]
    game.fixed=fixed_array(1,2)
    game.option <- some(DiffStats(health=10))
    game.action=DiffAction(move=DiffStats(health=5))
    game.nested=DiffNested(action=DiffAction(move=DiffStats(health=9)))
    return <- game
}
def diff_after(before:DiffGame) : DiffGame {
    var game <- derive_clone(before)
    game.title="New Arena"
    game.stats.health=75
    game.items[0].count=2
    game.items |> push(DiffItem(id=2,count=1))
    game.removed.resize(1)
    game.fixed[1]=3
    (game.option as some).health=11
    game.patch <- json_null(type<DiffStats>)
    game.action=DiffAction(move=DiffStats(health=6))
    game.nested=DiffNested(action=DiffAction(note="ready"))
    return <- game
}
