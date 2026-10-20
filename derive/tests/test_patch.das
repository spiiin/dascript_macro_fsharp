options gen2
require ../examples/patch_model.das
require daslib/rtti

[derive(debug=false,hash=false,clone=true,validate=true,patch=true)]
struct PatchOnly {value:int}

def detached_patch() {
    var inscope before <- patch_before()
    var inscope after <- patch_after(before)
    return <- derive_make_patch(before,after)
}
def detached_result() {
    var inscope current <- patch_before()
    var inscope patch <- detached_patch()
    return <- derive_apply_patch(current,patch,"game")
}
def check() {
    var inscope before <- patch_before()
    var inscope after <- patch_after(before)
    var inscope patch <- derive_make_patch(before,after)
    // Mutating snapshots' original sources cannot change the patch.
    before.items[0].mods[0]=88;after.items[0].mods[0]=99
    verify(patch.expected.items[0].mods[0]==10 && patch.desired.items[0].mods[0]==10)
    delete before;delete after
    var inscope current <- patch_before()
    current.stats.mana=25;current.revision=7;current.name="Local"
    (current.option as some).mana=3
    (current.action as stats).mana=4
    var inscope applied <- derive_apply_patch(current,patch,"game")
    verify(applied.ok && length(applied.errors)==0 && applied.value is some)
    verify((applied.value as some).stats.health==75 && (applied.value as some).stats.mana==25)
    verify((applied.value as some).revision==7 && (applied.value as some).name=="Local")
    verify(((applied.value as some).option as some).mana==3 && ((applied.value as some).action as stats).mana==4)
    verify(length((applied.value as some).items)==2 && (applied.value as some).fixed[1].count==6)
    verify((applied.value as some).field is null_value && ((applied.value as some).nested as action) is note)
    (applied.value as some).items[0].mods[0]=77
    verify(current.items[0].mods[0]==10 && patch.desired.items[0].mods[0]==10 && current.stats.health==100)
    var inscope again <- derive_apply_patch(current,patch)
    verify(again.ok && (again.value as some).items[0].mods[0]==10)
    // Conflicts accumulate in declaration order. Non-conflicting candidate edits are discarded.
    current.stats.health=90;current.items[0].mods[0]=11;current.fixed[0].count=8
    (current.option as some).health=12
    current.field <- json_present(PatchStats(health=1))
    current.action=PatchAction(note="local")
    current.nested=PatchNested(action=PatchAction(note="other"))
    var inscope conflicts <- derive_apply_patch(current,patch,"game")
    let paths=fixed_array("game.stats.health","game.items","game.fixed","game.option.health","game.field","game.action","game.nested.value")
    verify(!conflicts.ok && conflicts.value is none && length(conflicts.errors)==7)
    for(i in range(7)) {verify(conflicts.errors[i].path==paths[i] && conflicts.errors[i].code=="patch_conflict")}
    var inscope unchanged <- derive_clone(current)
    var inscope failedCommit <- derive_apply_patch_to(current,patch,"game")
    verify(length(failedCommit)==7 && derive_equal(current,unchanged))
    // A successful commit transfers the candidate only after full validation.
    delete current
    current <- patch_before()
    var inscope committed <- derive_apply_patch_to(current,patch,"game")
    verify(length(committed)==0 && derive_equal(current,patch.desired))
    var inscope repeated <- derive_apply_patch(current,patch)
    verify(!repeated.ok && repeated.value is none)
    // Empty patches preserve unrelated current changes but still validate the candidate.
    var inscope emptyPatch <- derive_make_patch(patch.expected,patch.expected)
    var inscope noChange <- derive_apply_patch(current,emptyPatch)
    verify(noChange.ok && derive_equal(current,noChange.value as some))
    current.stats.health=-1
    var inscope invalidEmpty <- derive_apply_patch(current,emptyPatch,"game")
    verify(!invalidEmpty.ok && invalidEmpty.value is none && invalidEmpty.errors[0].path=="game.stats.health")
    // Validation errors accumulate only after the conflict-free apply pass.
    var inscope valid <- patch_before()
    var inscope invalid <- derive_clone(valid)
    invalid.stats.health=-1;invalid.items[0].count=-2;invalid.fixed[1].count=-3
    (invalid.option as some).health=-4
    var inscope invalidPatch <- derive_make_patch(valid,invalid)
    var inscope rejected <- derive_apply_patch(valid,invalidPatch,"game")
    verify(!rejected.ok && rejected.value is none && length(rejected.errors)==5)
    let validationPaths=fixed_array("game.stats.health","game.items[0].count","game.fixed[1].count","game.option.health","game.stats")
    for(i in range(5)) {verify(rejected.errors[i].path==validationPaths[i])}
    var inscope rejectedCommit <- derive_apply_patch_to(valid,invalidPatch)
    verify(length(rejectedCommit)==5 && valid.stats.health==100 && valid.items[0].count==3)
    // Both branches are valid alone; the merge violates a cross-field invariant.
    var inscope mergeBase <- patch_before()
    var inscope mergeDesired <- derive_clone(mergeBase);mergeDesired.stats.health=30
    var inscope mergePatch <- derive_make_patch(mergeBase,mergeDesired)
    mergeBase.stats.mana=40
    var inscope mergeRejected <- derive_apply_patch(mergeBase,mergePatch,"game")
    verify(!mergeRejected.ok && length(mergeRejected.errors)==1 && mergeRejected.errors[0].code=="game_rule" && mergeBase.stats.health==100)
    var inscope detached <- detached_result()
    verify(detached.ok && (detached.value as some).stats.health==75 && length((detached.value as some).items)==2)
    let scalarPatch=derive_make_patch(1,2)
    var scalar=1
    var inscope scalarResult <- derive_apply_patch(scalar,scalarPatch)
    verify(scalarResult.ok && scalarResult.value as some==2 && scalar==1)
    var inscope scalarErrors <- derive_apply_patch_to(scalar,scalarPatch)
    verify(length(scalarErrors)==0 && scalar==2)
    let onlyPatch=derive_make_patch(PatchOnly(value=1),PatchOnly(value=2))
    var inscope only <- derive_apply_patch(PatchOnly(value=1),onlyPatch)
    verify(only.ok && (only.value as some).value==2)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive patch checks OK\n")
}
