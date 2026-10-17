options gen2
require ../lib/computation.das
[export]
def main() {
    var inscope r <- computation(MoveResultBuilder()) {
        var items & = move_ok([1,2]) |> bind
        return items
    }
}
