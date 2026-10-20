options gen2
module workflow_model public
require ./schema_model.das public

def derive_workflow(show:bool) {
    var inscope draft <- derive_builder(type<SchemaPlayer>)
    draft |> builder_name("Alice")
    draft |> builder_stats(SchemaStats(health=100))
    var inscope items:array<SchemaItem>
    items |> push(SchemaItem(id=1,count=3))
    draft |> builder_move_inventory(items)
    verify(length(items)==0)
    var inscope built <- derive_build(draft,"player")
    verify(built.ok && length(built.errors)==0)
    var inscope validation <- derive_validate(built.value as some,"player")
    verify(length(validation)==0)
    let json=derive_to_json(built.value as some)
    var inscope loaded <- derive_from_json(json,type<SchemaPlayer>,"player",true)
    verify(loaded.ok && derive_equal(loaded.value,built.value as some))
    var inscope edited <- derive_clone(loaded.value)
    edited.stats.health=75;edited.inventory[0].count=2
    verify(loaded.value.inventory[0].count==3)
    var inscope diff <- derive_diff(loaded.value,edited,"player")
    verify(length(diff)==2 && diff[0].path=="player.stats.health" && diff[1].path=="player.inventory[0].count")
    var inscope patch <- derive_make_patch(loaded.value,edited)
    var inscope current <- derive_clone(loaded.value)
    current.alias=some("local")
    var inscope applied <- derive_apply_patch(current,patch,"player")
    verify(applied.ok && (applied.value as some).stats.health==75 && (applied.value as some).inventory[0].count==2)
    verify((applied.value as some).alias as some=="local" && current.stats.health==100)
    // Conflict leaves current intact; validation rejection does too.
    current.stats.health=90
    var inscope conflict <- derive_apply_patch(current,patch,"player")
    verify(!conflict.ok && conflict.value is none && conflict.errors[0].path=="player.stats.health")
    current.stats.health=100
    var inscope invalid <- derive_clone(edited)
    invalid.stats.health=-1
    var inscope invalidPatch <- derive_make_patch(loaded.value,invalid)
    var inscope rejected <- derive_apply_patch(current,invalidPatch,"player")
    verify(!rejected.ok && rejected.value is none && rejected.errors[0].path=="player.stats.health" && current.stats.health==100)
    var inscope committed <- derive_apply_patch_to(current,patch,"player")
    verify(length(committed)==0 && current.stats.health==75 && current.alias as some=="local")
    // All snapshots own their arrays after inputs/draft have been destroyed.
    delete draft;delete built;delete loaded;delete edited
    verify(patch.desired.inventory[0].count==2 && (applied.value as some).inventory[0].count==2)
    if(show) {
        print("Loaded JSON: {json}\n")
        for(change in diff) {print("{change.path}: {change.before} -> {change.after}\n")}
        print("Committed health: {current.stats.health}, preserved alias: {current.alias as some}\n")
    }
}
