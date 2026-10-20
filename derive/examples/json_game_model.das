options gen2
module json_game_model public
require ../lib/derive.das public
var json_hook_calls=0
var json_hook_throws=false
[derive(json=true,validate=true,check="check_stats")]
struct JsonStats {
    @validate_min=0
    @validate_max=100
    health:int
    @validate_min=0
    @validate_max=50
    mana:int
}
def check_stats(value:JsonStats;path:string;var errors:array<ValidationIssue>) {
    json_hook_calls++
    if(json_hook_throws) {panic("JSON validation hook failed")}
    if(value.health==0 && value.mana>0) {validation_add(errors,validation_path(path,"mana"),"dead player has mana","dead_player_mana")}
}
[derive(json=true,validate=true)]
struct JsonPlayer {
    @json_name="displayName"
    @validate_non_empty
    name:string
    stats:JsonStats
    @json_required=false
    note:string="no note"
    @json_default=1
    @validate_min=1
    level:int
    @json_skip
    session:int=42
    tags:array<string>
}
[derive(json=true,validate=true)]
struct JsonGame {
    @validate_non_empty
    players:array<JsonPlayer>
    spawn:int[2]
}
def json_game_text() : string {
    return "\{\"players\":[\{\"displayName\":\"Alice\",\"stats\":\{\"health\":85,\"mana\":10\},\"tags\":[\"mage\",\"ёж\"]\}],\"spawn\":[3,4]\}"
}
