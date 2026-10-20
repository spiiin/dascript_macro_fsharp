options gen2
require ../examples/clone_model.das
require daslib/rtti
[derive(debug=false,equality=false,hash=false,clone=true)]
struct CloneOnly {values:array<int>}
[derive(clone=true)]
struct EmptyClone {}
variant CopyVariant {none;integer:int;text:string}
variant NonzeroEnumVariant {role:CloneRole}

def detached_copy() : CloneGame {
    var inscope source <- clone_game()
    return <- derive_clone(source)
}
def check() {
    var inscope source <- clone_game()
    var inscope copy <- derive_clone(source)
    verify(derive_equal(source,copy) && derive_hash(source)==derive_hash(copy))
    copy.inventory[0].mods[0]=30
    copy.inventory[0].mods |> push(31)
    copy.inventory[0].name="changed"
    copy.matrix[0][1]=40
    copy.fixed[1].mods[0]=50
    (copy.option as some).mods[0]=60
    (copy.patch as present).mods[0]=70
    (copy.action as item).mods[0]=80
    ((copy.nested as action) as item).mods[0]=90
    verify(source.inventory[0].mods[0]==3 && length(source.inventory[0].mods)==1 && source.inventory[0].name=="sword")
    verify(source.matrix[0][1]==20 && source.fixed[1].mods[0]==5)
    verify((source.option as some).mods[0]==6 && (source.patch as present).mods[0]==7)
    verify((source.action as item).mods[0]==8 && ((source.nested as action) as item).mods[0]==9)
    source.inventory[0].mods[0]=-1
    verify(copy.inventory[0].mods[0]==30)
    delete source
    verify(copy.matrix[0][1]==40 && (copy.action as item).mods[0]==80)
    var inscope detached <- detached_copy()
    verify(detached.inventory[0].mods[0]==3)
    var inscope again <- derive_clone(detached)
    verify(derive_equal(detached,again))
    var inscope empty:CloneGame
    var inscope emptyCopy <- derive_clone(empty)
    verify(derive_equal(empty,emptyCopy))
    var inscope nullField <- json_null(type<CloneItem>)
    var inscope nullCopy <- derive_clone(nullField)
    verify(nullCopy is null_value)
    var inscope noneValue <- none(type<CloneItem>)
    var inscope noneCopy <- derive_clone(noneValue)
    verify(noneCopy is none)
    var inscope missing <- json_missing(type<CloneItem>)
    var inscope missingCopy <- derive_clone(missing)
    verify(missingCopy is missing)
    var inscope nullable <- some(7)
    let nullableCopy=derive_clone(nullable)
    verify(nullableCopy is some && nullableCopy as some==7)
    var inscope action <- CloneAction(items <- _::derive_clone(detached.inventory))
    var inscope actionCopy <- derive_clone(action)
    (actionCopy as items)[0].mods[0]=77
    verify((action as items)[0].mods[0]==3)
    var inscope text <- CloneAction(note="hello")
    var inscope textCopy <- derive_clone(text)
    verify(textCopy is note && textCopy as note=="hello")
    var inscope idle <- CloneAction(idle)
    var inscope idleCopy <- derive_clone(idle)
    verify(idleCopy is idle)
    let scalar=derive_clone(CopyVariant(integer=42))
    verify(scalar is integer && scalar as integer==42)
    let role=derive_clone(NonzeroEnumVariant(role=CloneRole.Mage))
    verify(role as role==CloneRole.Mage)
    verify(derive_clone(true) && derive_clone("hi")=="hi" && derive_clone(3.5)==3.5)
    verify(derive_clone(CloneRole.Knight)==CloneRole.Knight)
    let fixed=derive_clone(fixed_array(1,2,3))
    verify(fixed[2]==3)
    let emptyStruct=derive_clone(EmptyClone())
    verify(derive_equal(emptyStruct,EmptyClone()))
    var inscope defaults=CloneDefaultContainer()
    let initializerCalls=clone_default_calls
    var inscope defaultsCopy <- derive_clone(defaults)
    verify(clone_default_calls==initializerCalls && defaultsCopy.items[0].values[0]==42)
    defaultsCopy.items[0].values[0]=17
    verify(defaults.items[0].values[0]==42)
    var inscope only:CloneOnly
    only.values |> push(5)
    var inscope onlyCopy <- derive_clone(only)
    onlyCopy.values[0]=6
    verify(only.values[0]==5)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive clone checks OK\n")
}
