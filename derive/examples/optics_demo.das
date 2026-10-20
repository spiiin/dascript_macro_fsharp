options gen2
require ./optics_model.das
require daslib/rtti

def check() {
    let health=optic("stats") |> optic_then("health")
    var inscope player <- optics_player()
    verify((player |> optic_get(health))==100)
    var inscope injured <- player |> optic_set(health,75)
    var inscope healed <- injured |> optic_over(health) <| $(hp:int) {return hp+10}
    verify(player.stats.health==100 && injured.stats.health==75 && healed.stats.health==85)
    var inscope snapshot <- healed |> optic_get("stats")
    snapshot.bonuses[0]=90
    verify(healed.stats.bonuses[0]==2 && player.stats.bonuses[0]==2)
    var inscope combined <- player |> optic_set(health,75) |> optic_over(health) <| $(hp:int) {return hp+10}
    verify(combined.stats.health==85 && player.stats.health==100)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    var inscope player <- optics_player()
    var inscope injured <- player |> optic_set("stats.health",75)
    var inscope healed <- injured |> optic_over("stats.health") <| $(hp:int) {return hp+10}
    print("Original: {player.stats.health}; injured: {injured.stats.health}; healed: {healed.stats.health}\n")
    print("Derive optics demo OK\n")
}
