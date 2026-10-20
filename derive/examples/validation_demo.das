options gen2
require ../lib/derive.das
[derive(validate=true)]
struct Stats {
    @validate_min=0
    @validate_max=100
    health:int
}
[derive(validate=true)]
struct Player {
    @validate_non_empty
    name:string
    stats:Stats
}
[export]
def main() {
    let p=Player(name="",stats=Stats(health=-10))
    var inscope errors <- derive_validate(p,"player")
    verify(length(errors)==2)
    for(error in errors) {print("{error.path}: {error.message}\n")}
    print("Derive validation demo OK\n")
}
