options gen2
require ../lib/computation.das
[export]
def main() {
    let bad = computation(WriterResultBuilder()) {
        some(1) |> bind
    }
    print("{bad}\n")
}
