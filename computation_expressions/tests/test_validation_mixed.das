options gen2
require ../lib/computation.das
require ../lib/validation_builder.das
[export]
def main() {
    let value = computation(ValidationBuilder()) { let x = result_ok(1) |> bind; return x }
    print("{value}")
}
