options gen2
require ../lib/computation.das
var steps = 0

def enemy_levels(first : int) {
    return <- computation(SequenceBuilder()) {
        var level = first
        while (true) {
            steps++
            yield level
            level++
        }
    }
}
[export]
def main() {
    var inscope levels <- enemy_levels(10)
    assert(steps==0)
    var taken = 0
    for (level in levels) {
        print("enemy level: {level}\n")
        taken++
        if (taken==3) { break }
    }
    assert(steps==3)
    var inscope equipment <- computation(SequenceBuilder(type<string>)) {
        let weapon = ["sword", "bow"] |> bind
        let level = [1,2,3] |> bind
        if (weapon=="sword" || level>=2) { yield "{weapon}:{level}" }
        // Bind runs the remaining body once for each input combination.
    }
    for (item in equipment) { print("{item}\n") }
    print("sequence demo OK\n")
}
