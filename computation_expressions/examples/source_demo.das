options gen2
require ../lib/computation_macro.das
require ../support/game_source_builder.das
[export]
def main() {
    var visited=0
    let result=computation(GameSourceBuilder(minimumHealth=10)) {
        let health=HealthCheck(health=25) |> bind
        for(target in TargetRange(first=100,count=3)) {
            print("Target {target}, health {health}\n")
            visited++
        }
        return health-visited
    }
    assert(result as ok==22 && visited==3)
    let blocked=computation(GameSourceBuilder(minimumHealth=10)) {
        HealthCheck(health=5) |> bind
        visited++
    }
    assert(blocked is error && visited==3)
    print("source protocol demo OK\n")
}
