options gen2
module game_model public
require ../lib/derive.das public
[derive]
struct Stats {health:int;mana:int}
[derive]
struct Player {name:string;stats:Stats;skills:array<string>}
def example_player() {
    var inscope player:Player
    player.name="Alice"
    player.stats=Stats(health=100,mana=25)
    player.skills <- ["dash","heal"]
    return <- player
}
