options gen2
require ../lib/computation.das
[export]
def main() {
    var inscope combinations <- computation(ListBuilder()) {
        let x = [1, 2] |> bind
        let y = [10, 20] |> bind
        return x + y
    }
    assert(length(combinations) == 4)
    print("Combinations: {combinations}\n")
    var inscope equipment <- computation(ListBuilder(type<string>)) {
        let weapon = ["sword", "bow"] |> bind
        let level = [1, 2, 3] |> bind
        if (weapon != "bow" || level >= 2) { return "{weapon}:level{level}" }
    }
    assert(length(equipment) == 5)
    print("Equipment: {equipment}\n")
    var inscope squares <- computation(ListBuilder()) {
        for (i in range(6)) {
            if (i % 2 == 0) { return i * i }
        }
    }
    assert(length(squares) == 3 && squares[2] == 16)
    print("Filtered loop: {squares}\nlist demo OK\n")
}
