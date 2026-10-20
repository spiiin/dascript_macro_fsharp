options gen2
require ./patch_model.das
[export]
def main() {
    var inscope before <- patch_before()
    var inscope after <- patch_after(before)
    var inscope patch <- derive_make_patch(before,after)
    var inscope current <- derive_clone(before)
    // Independent edits are preserved: neither field is modified by the patch.
    current.stats.mana=25;current.revision=7
    var inscope applied <- derive_apply_patch(current,patch,"game")
    verify(applied.ok)
    verify((applied.value as some).stats.health==75 && (applied.value as some).stats.mana==25 && (applied.value as some).revision==7)
    verify(current.stats.health==100)
    print("Patched health: {(applied.value as some).stats.health}, preserved mana: {(applied.value as some).stats.mana}\n")
    current.stats.health=90
    var inscope conflict <- derive_apply_patch(current,patch,"game")
    verify(!conflict.ok && conflict.value is none && conflict.errors[0].path=="game.stats.health")
    for(error in conflict.errors) {print("{error.path}: [{error.code}] {error.message}\n")}
    current.stats.health=100
    var inscope errors <- derive_apply_patch_to(current,patch,"game")
    verify(length(errors)==0 && current.stats.health==75 && current.stats.mana==25)
    // Validation rejects an otherwise conflict-free update atomically.
    var inscope invalid <- derive_clone(current)
    invalid.stats.health=-1
    var inscope invalidPatch <- derive_make_patch(current,invalid)
    var inscope invalidResult <- derive_apply_patch(current,invalidPatch,"game")
    verify(!invalidResult.ok && invalidResult.value is none && current.stats.health==75)
    print("Validation rejected update with {length(invalidResult.errors)} errors\n")
    print("Derive patch demo OK\n")
}
