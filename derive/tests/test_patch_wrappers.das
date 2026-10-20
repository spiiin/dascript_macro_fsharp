options gen2
require ../examples/patch_model.das
require daslib/rtti

enum PatchRole {
    Mage=10
    Knight=20
}
var default_calls=0
def patch_default_values() : array<int> {
    default_calls++
    var values:array<int>;values |> push(42);return <- values
}
[derive(clone=true,validate=true,patch=true)]
struct PatchDefault {values:array<int> = patch_default_values()}

def check() {
    var inscope optionValues:array<$Option<PatchStats>>
    var option <- none(type<PatchStats>);optionValues |> emplace(option)
    option <- some(PatchStats(health=10,mana=2));optionValues |> emplace(option)
    for(i in range(2)) {
        for(j in range(2)) {
            var inscope patch <- derive_make_patch(optionValues[i],optionValues[j])
            var inscope result <- derive_apply_patch(optionValues[i],patch,"option")
            verify(result.ok && derive_equal(result.value as some,optionValues[j]))
            var inscope unrelated <- derive_apply_patch(optionValues[1-i],patch,"option")
            if(i==j) {verify(unrelated.ok && derive_equal(unrelated.value as some,optionValues[1-i]))}
            else {verify(!unrelated.ok && unrelated.value is none && unrelated.errors[0].path=="option")}
        }
    }
    var inscope fields:array<$JsonField<PatchStats>>
    var field <- json_missing(type<PatchStats>);fields |> emplace(field)
    field <- json_null(type<PatchStats>);fields |> emplace(field)
    field <- json_present(PatchStats(health=10,mana=2));fields |> emplace(field)
    for(i in range(3)) {
        for(j in range(3)) {
            var inscope patch <- derive_make_patch(fields[i],fields[j])
            var inscope result <- derive_apply_patch(fields[i],patch,"field")
            verify(result.ok && derive_equal(result.value as some,fields[j]))
            var inscope other <- derive_apply_patch(fields[(i+1)%3],patch,"field")
            if(i==j) {verify(other.ok && derive_equal(other.value as some,fields[(i+1)%3]))}
            else {verify(!other.ok && other.errors[0].path=="field")}
        }
    }
    var inscope desired <- json_present(PatchStats(health=9,mana=2))
    var inscope fieldPatch <- derive_make_patch(fields[2],desired)
    var inscope current <- json_present(PatchStats(health=10,mana=3))
    var inscope fieldResult <- derive_apply_patch(current,fieldPatch,"field")
    verify(fieldResult.ok && ((fieldResult.value as some) as present).health==9 && ((fieldResult.value as some) as present).mana==3)
    // Variant changes of case are atomic; unchanged cases recurse into the payload.
    var inscope variants:array<PatchAction>
    var action <- PatchAction(idle);variants |> emplace(action)
    action <- PatchAction(stats=PatchStats(health=10,mana=2));variants |> emplace(action)
    action <- PatchAction(items <- default<array<PatchItem>>)
    var item <- patch_item(1,2);(action as items) |> emplace(item);variants |> emplace(action)
    action <- PatchAction(note="ready");variants |> emplace(action)
    for(i in range(4)) {
        for(j in range(4)) {
            var inscope patch <- derive_make_patch(variants[i],variants[j])
            var inscope result <- derive_apply_patch(variants[i],patch,"action")
            verify(result.ok && derive_equal(result.value as some,variants[j]))
            var inscope other <- derive_apply_patch(variants[(i+1)%4],patch,"action")
            if(i==j) {verify(other.ok && derive_equal(other.value as some,variants[(i+1)%4]))}
            else {verify(!other.ok && other.errors[0].path=="action")}
        }
    }
    var inscope beforeItems:array<PatchItem>
    item <- patch_item(1,2);beforeItems |> emplace(item)
    var inscope desiredItems <- derive_clone(beforeItems)
    desiredItems[0].count=3
    var inscope arrayPatch <- derive_make_patch(beforeItems,desiredItems)
    var inscope arrayResult <- derive_apply_patch(beforeItems,arrayPatch,"items")
    verify(arrayResult.ok && (arrayResult.value as some)[0].count==3)
    (arrayResult.value as some)[0].mods[0]=99
    verify(beforeItems[0].mods[0]==10 && arrayPatch.desired[0].mods[0]==10)
    var inscope locallyChanged <- derive_clone(beforeItems)
    locallyChanged[0].mods[0]=11
    var inscope arrayConflict <- derive_apply_patch(locallyChanged,arrayPatch,"items")
    verify(!arrayConflict.ok && arrayConflict.errors[0].path=="items")
    var inscope empty:array<PatchItem>
    var inscope removePatch <- derive_make_patch(beforeItems,empty)
    var inscope removal <- derive_apply_patch(beforeItems,removePatch)
    verify(removal.ok && length(removal.value as some)==0)
    var inscope addPatch <- derive_make_patch(empty,beforeItems)
    var inscope addition <- derive_apply_patch(empty,addPatch)
    verify(addition.ok && length(addition.value as some)==1)
    var inscope fixedBefore:PatchItem[2]
    fixedBefore[0] <- patch_item(1,2);fixedBefore[1] <- patch_item(2,3)
    var inscope fixedAfter <- derive_clone(fixedBefore)
    fixedAfter[1].count=4
    var inscope fixedPatch <- derive_make_patch(fixedBefore,fixedAfter)
    var inscope fixedResult <- derive_apply_patch(fixedBefore,fixedPatch,"fixed")
    verify(fixedResult.ok && (fixedResult.value as some)[1].count==4)
    var inscope fixedErrors <- derive_apply_patch_to(fixedBefore,fixedPatch)
    verify(length(fixedErrors)==0 && fixedBefore[1].count==4)
    let fixedScalarPatch=derive_make_patch(fixed_array(1,2),fixed_array(3,4))
    var inscope fixedScalar <- derive_apply_patch(fixed_array(1,2),fixedScalarPatch)
    verify(fixedScalar.ok && (fixedScalar.value as some)[1]==4)
    let rolePatch=derive_make_patch(PatchRole.Mage,PatchRole.Knight)
    var inscope roleResult <- derive_apply_patch(PatchRole.Mage,rolePatch)
    verify(roleResult.ok && roleResult.value as some==PatchRole.Knight)
    let textPatch=derive_make_patch("old","new")
    var text="old"
    var inscope textErrors <- derive_apply_patch_to(text,textPatch)
    verify(length(textErrors)==0 && text=="new")
    let boolPatch=derive_make_patch(false,true)
    var inscope boolResult <- derive_apply_patch(false,boolPatch)
    verify(boolResult.ok && boolResult.value as some)
    var inscope defaultBefore=PatchDefault()
    var inscope defaultAfter <- derive_clone(defaultBefore);defaultAfter.values[0]=7
    let initialized=default_calls
    var inscope defaultPatch <- derive_make_patch(defaultBefore,defaultAfter)
    var inscope defaultResult <- derive_apply_patch(defaultBefore,defaultPatch)
    verify(defaultResult.ok && default_calls==initialized && (defaultResult.value as some).values[0]==7)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive patch wrappers and arrays checks OK\n")
}
