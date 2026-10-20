options gen2
module patch_model public
require ../lib/derive.das public

[derive(clone=true,validate=true,patch=true,diff=true)]
struct PatchStats {
    @validate_min=0
    @validate_max=100
    health:int
    @validate_min=0
    mana:int
}
[derive(clone=true,validate=true,patch=true,diff=true)]
struct PatchItem {
    id:int
    @validate_min=0
    count:int
    mods:array<int>
}
variant PatchAction {idle;stats:PatchStats;items:array<PatchItem>;note:string}
variant PatchNested {empty;action:PatchAction}
[derive(clone=true,validate=true,patch=true,diff=true,check="check_patch_game")]
struct PatchGame {
    name:string
    stats:PatchStats
    items:array<PatchItem>
    fixed:PatchItem[2]
    option:$Option<PatchStats>
    field:$JsonField<PatchStats>
    action:PatchAction
    nested:PatchNested
    revision:int
}
def check_patch_game(value:PatchGame;path:string;var errors:array<ValidationIssue>) {
    if(value.stats.mana>value.stats.health) {validation_add(errors,validation_path(path,"stats"),"mana exceeds health","game_rule")}
}
def patch_item(id,count:int) : PatchItem {
    var item:PatchItem
    item.id=id;item.count=count;item.mods |> push(id*10)
    return <- item
}
def patch_before() : PatchGame {
    var game:PatchGame
    game.name="Arena";game.stats=PatchStats(health=100,mana=20)
    var item <- patch_item(1,3);game.items |> emplace(item)
    game.fixed[0] <- patch_item(2,4);game.fixed[1] <- patch_item(3,5)
    game.option <- some(PatchStats(health=10,mana=2))
    game.action=PatchAction(stats=PatchStats(health=8,mana=2))
    game.nested=PatchNested(action=PatchAction(stats=PatchStats(health=9,mana=1)))
    return <- game
}
def patch_after(before:PatchGame) : PatchGame {
    var game <- derive_clone(before)
    game.stats.health=75
    game.items[0].count=2
    var item <- patch_item(4,1);game.items |> emplace(item)
    game.fixed[1].count=6
    (game.option as some).health=11
    game.field <- json_null(type<PatchStats>)
    game.action=PatchAction(stats=PatchStats(health=7,mana=2))
    game.nested=PatchNested(action=PatchAction(note="ready"))
    return <- game
}
