options gen2
require ../lib/computation.das
[export]
def main() {
    let bad = computation(ResultBuilder()) {
        let value = some(1) |> bind
        return value
    }
    print("{bad}\n")
}
