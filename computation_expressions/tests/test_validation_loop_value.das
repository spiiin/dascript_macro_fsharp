options gen2
require ../lib/computation_macro.das
require ../lib/validation_builder.das
[export]
def main() {
    let value = computation(ValidationBuilder()) { for (i in range(3)) { return i }; return 0 }
    print("{value}")
}
