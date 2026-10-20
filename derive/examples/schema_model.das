options gen2
module schema_model public
require ../lib/derive.das public

enum SchemaRole {
    Warrior=1
    Mage=2
    Wizard=2
}
var schema_default_calls=0
def schema_default_items() : array<int> {schema_default_calls++;return <- [7,8]}
[derive(json=true,validate=true,clone=true,diff=true,patch=true)]
struct SchemaStats {
    @validate_min=0
    @validate_max=100
    health:int=100
}
[derive(json=true,validate=true,clone=true,diff=true,patch=true)]
struct SchemaItem {
    id:int
    @validate_min=1
    count:int=1
}
variant SchemaAction {idle;stats:SchemaStats;text:string;items:array<SchemaItem>}
def schema_item_key(item:SchemaItem) : int {return item.id}
def schema_check_name(value:string;path:string;var errors:array<ValidationIssue>) {
    if(value=="forbidden") {validation_add(errors,path,"name is reserved","reserved")}
}
def schema_check_player(value:SchemaPlayer;path:string;var errors:array<ValidationIssue>) {
    if(value.stats.health==0 && length(value.inventory)>0) {validation_add(errors,path,"dead player cannot carry items","game_rule")}
}
[derive(json=true,validate=true,clone=true,diff=true,patch=true,builder=true,check="schema_check_player")]
struct SchemaPlayer {
    @builder_required
    @json_name="displayName"
    @validate_non_empty
    @validate_check="schema_check_name"
    name:string
    role:SchemaRole=SchemaRole.Warrior
    stats:SchemaStats=SchemaStats()
    @validate_min_length=1
    @validate_unique_by="schema_item_key"
    inventory:array<SchemaItem>
    @json_required=false
    alias:$Option<string>
    @json_required=false
    bio:$JsonField<string>
    @json_required=false
    action:SchemaAction=SchemaAction(idle)
    @json_default="ok"
    @validate_min_length=2
    code:string="ok"
    @json_required=false
    defaults:array<int> = schema_default_items()
    @json_skip
    session:int=42
}
[derive(json=true,validate=true)]
struct SchemaTree {
    @validate_non_empty
    name:string
    children:array<SchemaTree>
}

[derive(json=true,validate=true,builder=true)]
struct SchemaPresence {
    @builder_required
    @json_required=false
    @validate_min=1
    @validate_max=9
    optional:$Option<int>
    required:$Option<int>
    @json_default=3
    value:int=9
}
