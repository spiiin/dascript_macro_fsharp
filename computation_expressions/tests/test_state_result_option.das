options gen2
require ../lib/computation.das
[export]
def main() {
    let bad = computation(StateResultBuilder(0)) { some(1) |> bind }
    print("{bad}\n")
}
