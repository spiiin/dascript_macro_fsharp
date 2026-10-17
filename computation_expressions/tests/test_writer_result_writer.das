options gen2
require ../lib/computation.das
[export]
def main() {
    let bad = computation(WriterResultBuilder()) {
        writer_value(1, "explicit conversion required") |> bind
    }
    print("{bad}\n")
}
