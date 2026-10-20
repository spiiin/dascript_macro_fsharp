options gen2
require ../lib/derive.das
require daslib/rtti
[derive]
struct Item {name:string;mods:array<int>}
[derive]
struct Inventory {items:array<Item>;matrix:array<array<int>>;tags:string[2]}

def inventory() {
    var inscope value:Inventory
    var inscope item:Item
    item.name="sword"
    item.mods <- [2,5]
    value.items |> emplace(item)
    var inscope row:array<int>
    row <- [1,2]
    value.matrix |> emplace(row)
    row <- [3]
    value.matrix |> emplace(row)
    value.tags=fixed_array("rare","equipped")
    return <- value
}
def check() {
    var inscope a <- inventory()
    var inscope b <- inventory()
    verify(derive_equal(a,b) && derive_hash(a)==derive_hash(b))
    verify(derive_debug(a)=="Inventory\{items=[Item\{name=\"sword\", mods=[2, 5]\}], matrix=[[1, 2], [3]], tags=[\"rare\", \"equipped\"]\}")
    verify(length(a.items)==1 && length(a.items[0].mods)==2 && length(b.matrix)==2)
    b.items[0].mods[1]=9
    verify(!derive_equal(a,b) && a.items[0].mods[1]==5)
    b.items[0].mods[1]=5
    b.matrix[0][0]=8
    verify(!derive_equal(a,b) && a.matrix[0][0]==1)
    b.matrix[0][0]=1
    b.tags[0]="common"
    verify(!derive_equal(a,b))
    b.tags=a.tags
    b.items[0].mods |> push(0)
    verify(!derive_equal(a,b))
    var inscope empty:Inventory
    var inscope other:Inventory
    verify(derive_equal(empty,other) && derive_hash(empty)==derive_hash(other))
    verify(!derive_equal(a,empty))
    var inscope left:array<int>
    var inscope right:array<int>
    verify(derive_debug(left)=="[]" && derive_equal(left,right) && derive_hash(left)==derive_hash(right))
    left <- [1,2];right <- [2,1]
    verify(!derive_equal(left,right))
    verify(derive_hash(left)!=derive_hash(right))
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive owning checks OK\n")
}
