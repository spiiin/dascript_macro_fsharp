options gen2
module validation_model public
require ../lib/derive.das public
var validation_custom_calls=0
[derive(validate=true,check="check_stats")]
struct ValidatedStats {
    @validate_min=0
    @validate_max=100
    health:int
    @validate_min=0
    @validate_max=50
    mana:int
}
def check_stats(value:ValidatedStats;path:string;var errors:array<ValidationIssue>) {
    validation_custom_calls++
    if(value.health==0 && value.mana>0) {
        validation_add(errors,validation_path(path,"mana"),"a defeated hero must have no mana")
    }
}
[derive(validate=true)]
struct ValidatedPlayer {
    @validate_non_empty
    @validate_min_length=2
    @validate_max_length=12
    name:string
    stats:ValidatedStats
    @validate_max_length=2
    skills:array<string>
}
[derive(debug=false,equality=false,hash=false,validate=true)]
struct GameConfig {
    @validate_non_empty
    @validate_max_length=3
    players:array<ValidatedPlayer>
}
def invalid_game_config() {
    var inscope config:GameConfig
    var inscope player:ValidatedPlayer
    player.name=""
    player.stats=ValidatedStats(health=-10,mana=60)
    player.skills <- ["dash","heal","fly"]
    config.players |> emplace(player)
    player.name="Bob"
    player.stats=ValidatedStats(health=0,mana=10)
    config.players |> emplace(player)
    return <- config
}
