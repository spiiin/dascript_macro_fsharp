options gen2
require ../lib/computation_macro.das
struct IncompleteBuilder {}
def ce_protocol(builder : IncompleteBuilder) { return CeValueProtocol() }
[export]
def main() { let value = computation(IncompleteBuilder()) { return 1 }; print("{value}") }
