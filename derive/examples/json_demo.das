options gen2
require ../lib/derive.das
[derive(json=true,validate=true)]
struct Stats {
    @validate_min=0
    @validate_max=100
    health:int
}
[derive(json=true,validate=true,check="check_player")]
struct Player {
    @json_name="displayName"
    @validate_non_empty
    name:string
    stats:Stats
    @json_default=1
    level:int
    @json_skip
    transient:int=42
}
def check_player(value:Player;path:string;var errors:array<ValidationIssue>) {
    if(value.name=="admin") {validation_add(errors,validation_path(path,"displayName"),"reserved name","reserved")}
}
[export]
def main() {
    var inscope loaded <- derive_from_json("\{\"displayName\":\"Alice\",\"stats\":\{\"health\":85\}\}",type<Player>,"player")
    verify(loaded.ok && loaded.value.name=="Alice" && loaded.value.level==1)
    print("{derive_to_json(loaded.value)}\n")
    var inscope bad <- derive_from_json("\{\"displayName\":\"admin\",\"stats\":\{\"health\":-5\}\}",type<Player>,"player")
    verify(!bad.ok && length(bad.errors)==2)
    for(issue in bad.errors) {print("{issue.path}: {issue.message} [{issue.code}]\n")}
    print("Derive JSON demo OK\n")
}
