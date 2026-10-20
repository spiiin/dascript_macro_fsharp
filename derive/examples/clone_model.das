options gen2
module clone_model public
require ../lib/derive.das public

enum CloneRole {
    Knight=1
    Mage=2
}
[derive(clone=true)]
struct CloneItem {name:string;mods:array<int>}
variant CloneAction {
    idle
    item:CloneItem
    items:array<CloneItem>
    note:string
    role:CloneRole
}
variant CloneNested {empty;action:CloneAction}
[derive(clone=true)]
struct CloneGame {
    title:string
    inventory:array<CloneItem>
    matrix:array<array<int>>
    fixed:CloneItem[2]
    option:$Option<CloneItem>
    patch:$JsonField<CloneItem>
    action:CloneAction
    nested:CloneNested
}
def clone_item(name:string;modifier:int) : CloneItem {
    var item:CloneItem
    item.name=name
    item.mods |> push(modifier)
    return <- item
}
def clone_game() : CloneGame {
    var game:CloneGame
    game.title="Arena"
    var item <- clone_item("sword",3)
    game.inventory |> emplace(item)
    var row:array<int>
    row <- [10,20]
    game.matrix |> emplace(row)
    game.fixed[0] <- clone_item("shield",4)
    game.fixed[1] <- clone_item("boots",5)
    item <- clone_item("potion",6)
    game.option <- move_some(item)
    item <- clone_item("helmet",7)
    game.patch <- json_move_present(item)
    game.action <- CloneAction(item <- clone_item("bow",8))
    game.nested <- CloneNested(action <- CloneAction(item <- clone_item("staff",9)))
    return <- game
}

// Clone must not rerun user field initializers, including inside fixed arrays.
var clone_default_calls=0
def clone_default_values() : array<int> {
    clone_default_calls++
    var values:array<int>
    values |> push(42)
    return <- values
}
[derive(clone=true)]
struct CloneDefaultItem {values:array<int> = clone_default_values()}
def clone_default_item() : CloneDefaultItem {return CloneDefaultItem()}
[derive(clone=true)]
struct CloneDefaultContainer {items:CloneDefaultItem[1] = fixed_array(clone_default_item())}
