options gen2
require ../lib/computation_macro.das
struct MissingBuilder {}
[export]
def main() { let value = computation(MissingBuilder()) { return 1 }; print("{value}") }
