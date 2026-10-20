options gen2
module builder_model public
require ../lib/derive.das public
[derive(builder=true,validate=true,clone=true)]
struct BuildPlayer {
    @builder_required
    @validate_non_empty
    name:string
    @validate_min=0
    @validate_max=100
    health:int=100
    inventory:array<int>
    @builder_required
    note:$Option<string> = none(type<string>)
}
