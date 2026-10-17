options gen2
require ../lib/computation.das
struct Inventory { items:array<int> }
def load_inventory() {
    var inscope inventory:Inventory
    inventory.items |> push(101)
    return <- move_ok(inventory)
}
def grant_reward() {
    return <- computation(MoveResultBuilder()) {
        var inventory & = load_inventory() |> bind
        inventory.items |> push(202)
        return <- inventory
    }
}
def consume_inventory(var inventory:Inventory) : int {
    return length(inventory.items)
}
[export]
def main() {
    var inscope result <- grant_reward()
    assert(result is ok)
    let count=consume_inventory(result as ok)
    assert(count==2)
    var inscope optional <- computation(MoveOptionBuilder()) {
        var items & = move_some([10,20]) |> bind
        items |> push(30)
        return <- items
    }
    assert(length(optional as some)==3)
    print("move-only CE demo OK\n")
}
