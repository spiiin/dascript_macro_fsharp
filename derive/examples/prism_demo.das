options gen2
require ./prism_model.das
require daslib/rtti
var calls=0
def check() {
    var inscope player <- prism_player()
    let health=prism("optional") |> prism_then("some.health")
    var inscope snapshot <- player |> prism_try_get(health)
    verify(snapshot is some && (snapshot as some)==100)
    var inscope healed <- player |> prism_over(health) <| $(hp:int) {return hp+10}
    verify((healed.optional as some).health==110 && (player.optional as some).health==100)
    delete player.field
    player.field <- json_null(type<OpticStats>)
    calls=0
    var inscope unchanged <- player |> prism_over("field.present.health") <| $(hp:int) {calls++;return hp-10}
    verify(calls==0 && unchanged.field is null_value)
    verify(unchanged |> prism_matches("field.null_value"))
    var inscope changed <- player |> prism_set("action.stats.bonuses",[4,5])
    verify((changed.action as stats).bonuses[0]==4 && (player.action as stats).bonuses[0]==2)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive prism demo OK\n")
}
