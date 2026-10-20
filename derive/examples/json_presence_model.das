options gen2
module json_presence_model public
require ../lib/derive.das public
var presence_hook_calls=0
var presence_hook_throws=false
[derive(json=true,validate=true,check="check_detail")]
struct PresenceDetail {
    @validate_min=0
    score:int
    values:array<int>
}
def check_detail(value:PresenceDetail;path:string;var errors:array<ValidationIssue>) {
    presence_hook_calls++
    if(presence_hook_throws) {panic("presence hook failed")}
}
[derive(json=true,validate=true)]
struct PresenceUser {
    @json_name="displayName"
    name:string
    nickname:$Option<string>
    @json_required=false
    @validate_min_length=2
    bio:$JsonField<string>
    @json_required=false
    detail:$Option<PresenceDetail>
    @json_required=false
    patch:$JsonField<PresenceDetail>
    @json_required=false
    @validate_min=1
    rank:$Option<int>
    @json_required=false
    @validate_min=1
    level:$JsonField<int>
    @json_skip
    session:int=42
}
