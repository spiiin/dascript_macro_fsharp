options gen2
require ../examples/builder_model.das
require daslib/rtti

[derive(clone=true,validate=true)]
struct BuilderChild {values:array<int>}
variant BuilderChoice {idle;child:BuilderChild}
[derive(builder=true,validate=true)]
struct BuilderNested {
    child:BuilderChild
    optional:$Option<BuilderChild>
    field:$JsonField<BuilderChild>
    choice:BuilderChoice
    fixed:int[2]=fixed_array(3,4)
}
[derive(builder=true,validate=true)]
struct BuilderScalar {value:int=8}

def checkNested() {
    var inscope draft <- derive_builder(type<BuilderNested>)
    var inscope child:BuilderChild
    child.values <- [7,8]
    draft |> builder_child(child)
    var inscope optional <- move_some(derive_clone(child))
    draft |> builder_optional(optional)
    var inscope field <- json_move_present(derive_clone(child))
    draft |> builder_field(field)
    var inscope choice <- BuilderChoice(child <- derive_clone(child))
    draft |> builder_choice(choice)
    var inscope result <- derive_build(draft)
    if(!(result.ok && (result.value as some).fixed[1]==4)) {panic("builder ownership check 31 failed")}
    (result.value as some).child.values[0]=9
    ((result.value as some).optional as some).values[0]=10
    ((result.value as some).field as present).values[0]=11
    ((result.value as some).choice as child).values[0]=12
    if(!(child.values[0]==7 && draft.data.child.values[0]==7)) {panic("builder ownership check 36 failed")}
    if(!((optional as some).values[0]==7 && (field as present).values[0]==7 && (choice as child).values[0]==7)) {panic("builder ownership check 37 failed")}
    var inscope scalar <- derive_builder(type<BuilderScalar>)
    var inscope scalarResult <- derive_build(scalar)
    if(!(scalarResult.ok && (scalarResult.value as some).value==8)) {panic("builder ownership check 40 failed")}
}
def check() {
    let nestedBaseline=heap_bytes_allocated()
    checkNested()
    if(heap_bytes_allocated()!=nestedBaseline) {panic("builder nested heap check failed")}
    var inscope draft <- derive_builder(type<BuildPlayer>)
    var inscope missing <- derive_build(draft,"player")
    if(!(!missing.ok && missing.value is none && length(missing.errors)==2)) {panic("builder ownership check 46 failed")}
    if(!(missing.errors[0].path=="player.name" && missing.errors[1].path=="player.note")) {panic("builder ownership check 47 failed")}
    if(!(missing.errors[0].code=="builder_required")) {panic("builder ownership check 48 failed")}
    draft |> builder_name("")
    draft |> builder_note(none(type<string>))
    draft |> builder_health(-1)
    var inscope invalid <- derive_build(draft)
    if(!(!invalid.ok && invalid.value is none && length(invalid.errors)==2)) {panic("builder ownership check 53 failed")}
    if(!(invalid.errors[0].path=="name" && invalid.errors[1].path=="health")) {panic("builder ownership check 54 failed")}
    draft |> builder_name("Alice")
    draft |> builder_health(80)
    var inscope input <- [1,2,3]
    draft |> builder_inventory(input)
    input[0]=99
    var inscope first <- derive_build(draft)
    var inscope second <- derive_build(draft)
    if(!(first.ok && second.ok && (first.value as some).inventory[0]==1)) {panic("builder ownership check 62 failed")}
    (first.value as some).inventory[0]=7
    if(!((second.value as some).inventory[0]==1 && draft.data.inventory[0]==1)) {panic("builder ownership check 64 failed")}
    var inscope moved <- [4,5]
    draft |> builder_move_inventory(moved)
    if(!(length(moved)==0 && draft.data.inventory[0]==4)) {panic("builder ownership check 67 failed")}
    draft |> builder_inventory(input)
    if(!(draft.data.inventory[0]==99)) {panic("builder ownership check 69 failed")}
    var inscope movedResult <- derive_build(draft)
    if(!(movedResult.ok && (movedResult.value as some).note is none)) {panic("builder ownership check 71 failed")}
    delete draft
    if(!((movedResult.value as some).inventory[0]==99)) {panic("builder ownership check 73 failed")}
    var inscope defaults <- derive_builder(type<BuildPlayer>)
    defaults |> builder_name("Bob")
    defaults |> builder_note(some("hello"))
    var inscope defaultResult <- derive_build(defaults)
    if(!(defaultResult.ok && (defaultResult.value as some).health==100)) {panic("builder ownership check 78 failed")}
    if(!((defaultResult.value as some).note as some=="hello")) {panic("builder ownership check 79 failed")}
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();if(heap_bytes_allocated()!=baseline) {panic("builder repeat heap check failed")}}
    print("Derive builder checks OK\n")
}
