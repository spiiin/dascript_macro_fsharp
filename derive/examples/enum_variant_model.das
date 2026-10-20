options gen2
module enum_variant_model public
require ../lib/derive.das public
enum CharacterRole {
    Warrior=1
    Mage=10
    Wizard=10
    Rogue=30
}
enum WideRole:uint64 {
    Low=1ul
    High=9223372036854775808ul
    Max=18446744073709551615ul
}
enum SmallRole:int8 {
    Negative=-7
    Positive=12
}
enum SignedRole:int64 {
    Negative=-9007199254740993l
    Positive=9007199254740993l
}
var sum_hook_throws=false
var sum_hook_calls=0
[derive(json=true,validate=true,check="check_move")]
struct MoveCommand {
    @validate_min=0
    x:int
    y:int
    values:array<int>
    @json_required=false
    note:string="new"
}
def check_move(value:MoveCommand;path:string;var errors:array<ValidationIssue>) {
    sum_hook_calls++
    if(sum_hook_throws) {panic("sum validation failed")}
}
variant GameCommand {idle;move:MoveCommand;text:string;batch:array<MoveCommand>;nullable:$Option<MoveCommand>}
variant NestedCommand {stop;inner:GameCommand}
[derive(json=true,validate=true)]
struct CommandConfig {
    role:CharacterRole=CharacterRole.Warrior
    commands:array<GameCommand>
    @json_required=false
    optional:$Option<GameCommand>
    @json_required=false
    patch:$JsonField<GameCommand>
}
