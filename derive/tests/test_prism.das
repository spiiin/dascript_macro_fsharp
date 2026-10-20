options gen2
require ../examples/prism_model.das
require daslib/rtti
var calls=0
var source_calls=0
def replacement() : array<int> {calls++;return <- [6,7]}
def source() : PrismNest {source_calls++;return <- prism_nest()}
struct ReadOnlyPrism {value:$Option<int>;storage:array<int>}
def read_only() : ReadOnlyPrism {
    var result:ReadOnlyPrism
    result.value=some(7)
    result.storage <- [1,2]
    return <- result
}
variant PrismLookalike {missing;null_value:string;present:int}

def check() {
    let health=prism("optional") |> prism_then("some.health")
    var inscope player <- optics_player()
    // None does not call either a modifier or a replacement factory.
    calls=0
    var inscope absent <- player |> prism_try_get(health)
    verify(absent is none && !(player |> prism_matches(health)))
    var inscope unchanged <- player |> prism_over(health) <| $(hp:int) {calls++;return hp-10}
    var inscope skipped <- player |> prism_set("optional.some.bonuses",replacement())
    verify(calls==0 && unchanged.optional is none && skipped.optional is none)
    unchanged.inventory[0]=88
    verify(player.inventory[0]==1)
    // Missing and null remain distinct when the present path does not match.
    for(state in range(2)) {
        if(state==0) {player.field <- json_missing(type<OpticStats>)}
        else {player.field <- json_null(type<OpticStats>)}
        var inscope noValue <- player |> prism_try_get("field.present.bonuses")
        var inscope noChange <- player |> prism_over("field.present.health") <| $(hp:int) {calls++;return hp+1}
        var inscope noSet <- player |> prism_set("field.present.bonuses",replacement())
        verify(noValue is none && calls==0)
        verify(variant_index(player.field)==variant_index(noChange.field) && variant_index(player.field)==variant_index(noSet.field))
        verify((player |> prism_matches("field.missing"))==(state==0))
        verify((player |> prism_matches("field.null_value"))==(state==1))
    }
    verify(player |> prism_matches("action.idle"))
    var inscope noCase <- player |> prism_over("action.stats.health") <| $(hp:int) {calls++;return hp+1}
    verify(calls==0 && noCase.action is idle)
    player.action <- OpticAction(items <- [9,10])
    var inscope wrongCase <- player |> prism_set("action.stats.bonuses",replacement())
    verify(calls==0 && wrongCase.action is items && (wrongCase.action as items)[0]==9)
    // All three matching wrappers support independent snapshots and updates.
    var inscope full <- prism_player()
    var inscope someHp <- full |> prism_try_get(health)
    verify(someHp is some && (someHp as some)==100)
    var inscope changed <- full |> prism_over(health) <| $(hp:int) {calls++;return hp-10}
    verify(calls==1 && (changed.optional as some).health==90 && (full.optional as some).health==100)
    var inscope snapshot <- full |> prism_try_get("field.present")
    (snapshot as some).bonuses[0]=80
    verify((full.field as present).bonuses[0]==2)
    var inscope input <- [20,30]
    var inscope setBorrowed <- full |> prism_set("action.stats.bonuses",input)
    input[0]=21
    verify((setBorrowed.action as stats).bonuses[0]==20 && (full.action as stats).bonuses[0]==2)
    var inscope setTemporary <- full |> prism_set("field.present.bonuses",replacement())
    verify(calls==2 && (setTemporary.field as present).bonuses[0]==6)
    var inscope grown <- full |> prism_over("optional.some.bonuses") <| $(values:array<int>) {
        var result <- derive_clone(values)
        result |> push(4)
        return <- result
    }
    verify(length((grown.optional as some).bonuses)==3 && length((full.optional as some).bonuses)==2)
    // Composition with total Optics consumes intermediate owning roots safely.
    var inscope chained <- full |> prism_set(health,70) |> optic_set("name","Bob") |> prism_over("field.present.health") <| $(hp:int) {return hp+5}
    verify(chained.name=="Bob" && (chained.optional as some).health==70 && (chained.field as present).health==105)
    verify(full.name=="Alice" && (full.optional as some).health==100)
    // No partial segment also has useful semantics: Some(None) differs from None.
    var inscope nestedNone <- player |> prism_try_get("optional")
    verify(nestedNone is some && (nestedNone as some) is none)
    var inscope nest <- prism_nest()
    let deep=prism("player.some.field.present.health")
    var inscope deepGet <- nest |> prism_try_get(deep)
    verify(deepGet is some && (deepGet as some)==100)
    var inscope deepSet <- nest |> prism_set(deep,3)
    verify(((deepSet.player as some).field as present).health==3 && ((nest.player as some).field as present).health==100)
    delete (nest.player as some).field
    (nest.player as some).field <- json_null(type<OpticStats>)
    var inscope innerMiss <- nest |> prism_try_get(deep)
    var inscope innerUpdate <- nest |> prism_over(deep) <| $(hp:int) {calls++;return hp+1}
    verify(innerMiss is none && (innerUpdate.player as some).field is null_value && calls==2)
    delete nest.player
    var inscope shortCircuit <- nest |> prism_try_get(deep)
    var inscope shortUpdate <- nest |> prism_over(deep) <| $(hp:int) {calls++;return hp+1}
    verify(shortCircuit is none && shortUpdate.player is none && calls==2)
    // An owned root is evaluated once, and kept alive until the snapshot is ready.
    source_calls=0
    var inscope owned <- source() |> prism_try_get("player.some")
    verify(source_calls==1 && (owned as some).inventory[0]==1)
    (owned as some).inventory[0]=99
    verify(source() |> prism_matches(deep))
    var inscope ownedChanged <- source() |> prism_set(deep,5)
    verify(source_calls==3 && ((ownedChanged.player as some).field as present).health==5)
    // Root itself may be Option, JsonField or an ordinary variant.
    var inscope option <- full.optional |> prism_over("some.health") <| $(hp:int) {return hp+1}
    var inscope field <- full.field |> prism_set("present.health",2)
    var inscope action <- full.action |> prism_try_get("stats.bonuses")
    verify((option as some).health==101 && (field as present).health==2 && (action as some)[0]==2)
    var inscope scalar <- some(3) |> prism_try_get("some")
    verify(scalar is some && (scalar as some)==3)
    // Snapshot reads do not require Clone on the containing root.
    var inscope readOnly <- read_only()
    var inscope readValue <- readOnly |> prism_try_get("value.some")
    var inscope ownedReadValue <- read_only() |> prism_try_get("value.some")
    verify((readValue as some)==7 && (ownedReadValue as some)==7 && length(readOnly.storage)==2)
    // Cases are resolved by their declared payload, not magic wrapper names.
    let ordinary=PrismLookalike(null_value="text")
    var inscope text <- ordinary |> prism_try_get("null_value")
    verify(text is some && (text as some)=="text" && !(ordinary |> prism_matches("present")))
    // get-set and last-write laws on matching cases; nonmatching updates stay absent.
    let hp=(someHp as some)
    var inscope same <- full |> prism_set(health,hp)
    verify(derive_equal(full,same))
    var inscope twice <- full |> prism_set(health,1) |> prism_set(health,2)
    var inscope once <- full |> prism_set(health,2)
    verify(derive_equal(twice,once))
    delete full
    verify((snapshot as some).bonuses[0]==80 && (action as some)[0]==2 && (owned as some).inventory[0]==99)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive prism checks OK\n")
}
