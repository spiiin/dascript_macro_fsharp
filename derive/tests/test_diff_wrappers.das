options gen2
require ../examples/diff_model.das
require daslib/rtti

enum DiffRole {
    Mage=10
    Wizard=10
    Knight=20
}
variant VoidDiff {idle;stop}

def check() {
    var inscope optionValues:array<$Option<array<int>>>
    var option <- none(type<array<int>>)
    optionValues |> emplace(option)
    var values:array<int>;values <- [1,2]
    option <- move_some(values)
    optionValues |> emplace(option)
    for(i in range(2)) {
        for(j in range(2)) {
            var inscope changes <- derive_diff(optionValues[i],optionValues[j],"option")
            verify(length(changes)==(i==j ? 0 : 1))
            if(i!=j) {
                verify(changes[0].kind=="state" && changes[0].path=="option")
                verify(changes[0].before==derive_debug(optionValues[i]) && changes[0].after==derive_debug(optionValues[j]))
            }
        }
    }
    var inscope fields:array<$JsonField<array<int>>>
    var field <- json_missing(type<array<int>>);fields |> emplace(field)
    field <- json_null(type<array<int>>);fields |> emplace(field)
    values <- [1,2];field <- json_move_present(values);fields |> emplace(field)
    for(i in range(3)) {
        for(j in range(3)) {
            var inscope changes <- derive_diff(fields[i],fields[j],"patch")
            verify(length(changes)==(i==j ? 0 : 1))
            if(i!=j) {
                verify(changes[0].kind=="state" && changes[0].path=="patch")
                verify(changes[0].before==derive_debug(fields[i]) && changes[0].after==derive_debug(fields[j]))
            }
        }
    }
    values <- [1,3]
    var inscope changedOption <- move_some(values)
    var inscope optionChanges <- derive_diff(optionValues[1],changedOption,"option")
    verify(length(optionChanges)==1 && optionChanges[0].path=="option[1]" && optionChanges[0].kind=="changed")
    values <- [1,3]
    var inscope changedField <- json_move_present(values)
    var inscope fieldChanges <- derive_diff(fields[2],changedField,"patch")
    verify(length(fieldChanges)==1 && fieldChanges[0].path=="patch[1]")
    verify((optionValues[1] as some)[1]==2 && (fields[2] as present)[1]==2)
    var inscope actionA <- DiffAction(items <- default<array<DiffItem>>)
    (actionA as items) |> push(DiffItem(id=1,count=1))
    var inscope actionB <- derive_clone(actionA)
    (actionB as items)[0].count=2
    (actionB as items) |> push(DiffItem(id=2,count=3))
    var inscope actionChanges <- derive_diff(actionA,actionB,"action")
    verify(length(actionChanges)==2 && actionChanges[0].path=="action.value[0].count" && actionChanges[1].path=="action.value[1]" && actionChanges[1].kind=="added")
    var inscope idle <- DiffAction(idle)
    var inscope caseChanges <- derive_diff(actionA,idle,"action")
    verify(length(caseChanges)==1 && caseChanges[0].kind=="case" && caseChanges[0].after=="idle")
    var inscope voidSame <- derive_diff(VoidDiff(idle),VoidDiff(idle))
    var inscope voidDifferent <- derive_diff(VoidDiff(idle),VoidDiff(stop))
    verify(length(voidSame)==0 && length(voidDifferent)==1 && voidDifferent[0].before=="idle" && voidDifferent[0].after=="stop")
    var inscope enumAlias <- derive_diff(DiffRole.Mage,DiffRole.Wizard)
    var inscope enumDifferent <- derive_diff(DiffRole.Mage,DiffRole.Knight)
    verify(length(enumAlias)==0 && length(enumDifferent)==1 && enumDifferent[0].kind=="changed")
    var inscope zero <- derive_diff(0.0,-0.0)
    verify(length(zero)==0)
    var inscope boolean <- derive_diff(false,true)
    verify(length(boolean)==1 && boolean[0].before=="false" && boolean[0].after=="true")
    var inscope strings <- derive_diff("a\nb","new")
    verify(length(strings)==1 && strings[0].before=="\"a\\nb\"")
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive diff wrappers and variants checks OK\n")
}
