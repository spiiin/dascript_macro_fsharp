options gen2
require ../examples/optics_model.das
require daslib/rtti
require strings
var optics_calls=0
def optics_array() : array<int> {optics_calls++;return <- [6,7]}
def optics_source() : OpticPlayer {optics_calls++;return <- optics_player()}

[derive(clone=true)]
struct ScalarOptic {value:int}
struct ReadOnlyOptic {value:int}

def check() {
    let health=optic("stats") |> optic_then("health")
    let stats=optic("stats")
    let bonuses=stats |> optic_then("bonuses")
    var inscope original <- optics_player()
    verify((original |> optic_get(health))==100)
    var inscope snapshot <- original |> optic_get(stats)
    snapshot.bonuses[0]=90
    verify(original.stats.bonuses[0]==2)
    var inscope replaced <- original |> optic_set(stats,snapshot)
    snapshot.bonuses[0]=91
    verify(replaced.stats.bonuses[0]==90 && original.stats.bonuses[0]==2)
    replaced.inventory[0]=99
    verify(original.inventory[0]==1)
    var inscope input <- [10,20]
    var inscope fromInput <- original |> optic_set(bonuses,input)
    input[0]=11
    verify(fromInput.stats.bonuses[0]==10 && length(input)==2)
    optics_calls=0
    var inscope fromTemporary <- original |> optic_set("inventory",optics_array())
    verify(optics_calls==1 && fromTemporary.inventory[0]==6)
    var inscope fromLiteral <- original |> optic_set("inventory",[8,9])
    verify(fromLiteral.inventory[1]==9)
    var inscope chained <- original |> optic_set(health,75) |> optic_set("name","Bob") |> optic_over(health) <| $(hp:int) {return hp+10}
    verify(chained.stats.health==85 && original.stats.health==100 && chained.name=="Bob" && original.name=="Alice")
    var inscope grown <- original |> optic_over("inventory") <| $(values:array<int>) {
        var result <- derive_clone(values)
        result |> push(4)
        return <- result
    }
    verify(length(grown.inventory)==4 && length(original.inventory)==3)
    optics_calls=0
    let fromCall=optics_source() |> optic_get(health)
    verify(fromCall==100 && optics_calls==1)
    var inscope ownedSnapshot <- optics_source() |> optic_get(bonuses)
    verify(ownedSnapshot[0]==2 && optics_calls==2)
    var inscope ownedUpdate <- optics_source() |> optic_set(health,25)
    verify(ownedUpdate.stats.health==25 && optics_calls==3)
    // Copyable roots and read-only roots without derive Clone.
    let scalar=ScalarOptic(value=3)
    let scalarCopy=scalar |> optic_set("value",4)
    verify(scalar.value==3 && scalarCopy.value==4)
    verify((ReadOnlyOptic(value=9) |> optic_get("value"))==9)
    // A stable projected owner is borrowed, not consumed.
    var inscope projected <- original.stats |> optic_set("health",12)
    verify(projected.health==12 && original.stats.health==100)
    var inscope players:array<OpticPlayer>
    var player <- optics_player()
    players |> emplace(player)
    var inscope indexed <- players[0] |> optic_set(health,11)
    verify(indexed.stats.health==11 && players[0].stats.health==100)
    var state=OpticStats(health=7)
    let rootBefore=state.health
    var inscope stateCopy <- state |> optic_set("health",8)
    verify(stateCopy.health==8 && state.health==rootBefore)
    var inscope optional <- move_some(derive_clone(original.stats))
    var inscope withOption <- original |> optic_set("optional",optional)
    (optional as some).bonuses[0]=44
    verify((withOption.optional as some).bonuses[0]==2)
    var inscope field <- json_move_present(derive_clone(original.stats))
    var inscope withField <- original |> optic_set("field",field)
    var inscope action <- OpticAction(stats <- derive_clone(original.stats))
    var inscope withAction <- original |> optic_set("action",action)
    (action as stats).bonuses[0]=55
    verify((withAction.action as stats).bonuses[0]==2)
    var inscope fieldSnapshot <- withField |> optic_get("field")
    (fieldSnapshot as present).bonuses[0]=66
    verify((withField.field as present).bonuses[0]==2)
    // Owning intermediates with simultaneously active wrapper/variant payloads.
    var inscope all <- withOption |> optic_set("field",field) |> optic_set("action",action)
    var inscope actionSnapshot <- all |> optic_set(health,1) |> optic_set("name","Snapshot") |> optic_get("action")
    (actionSnapshot as stats).bonuses[0]=77
    verify((all.action as stats).bonuses[0]==55 && (all.optional as some).bonuses[0]==2)
    verify((all.field as present).bonuses[0]==2 && all.stats.health==100)
    var inscope overVariant <- all |> optic_over("action") <| $(value:OpticAction) : OpticAction {return <- derive_clone(value)}
    (overVariant.action as stats).bonuses[0]=78
    verify((all.action as stats).bonuses[0]==55)
    let fixed=original |> optic_get("fixed")
    var inscope withFixed <- original |> optic_set("fixed",fixed_array(9,10))
    verify(fixed[0]==4 && withFixed.fixed[0]==9 && original.fixed[0]==4)
    // Lens laws on complete paths: get-put, put-get, put-put.
    let hp=original |> optic_get(health)
    var inscope unchanged <- original |> optic_set(health,hp)
    verify(derive_equal(original,unchanged))
    var inscope a <- original |> optic_set(health,20) |> optic_set(health,30)
    var inscope b <- original |> optic_set(health,30)
    verify((a |> optic_get(health))==30 && derive_equal(a,b))
    delete original
    verify(ownedSnapshot[0]==2 && fromInput.stats.bonuses[0]==10 && (withOption.optional as some).bonuses[0]==2)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();if(heap_bytes_allocated()!=baseline) {panic("optics repeat leaked heap")}}
    print("Derive optics checks OK\n")
}
