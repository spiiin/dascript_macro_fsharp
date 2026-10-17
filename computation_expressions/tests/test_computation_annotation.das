options gen2
require ../lib/computation.das
[export]
def main() {
    let bad = computation(OptionBuilder()) {
        let value : string = some(1) |> bind
        return value
    }
    print("{bad}\n")
}
