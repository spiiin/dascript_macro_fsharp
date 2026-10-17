options gen2
require ../lib/computation_macro.das
struct InvalidBuilder {}
def ce_protocol(builder : InvalidBuilder) { return 123 }
[export]
def main() { let value = computation(InvalidBuilder()) { return 1 }; print("{value}") }
