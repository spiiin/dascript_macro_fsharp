options gen2
require ../lib/computation_macro.das
struct InvalidLoop {}
def ce_protocol(builder:InvalidLoop) {return CeValueProtocol()}
def ce_zero(builder:InvalidLoop) {return 0}
def ce_while(builder:InvalidLoop; condition:block<():bool>; body:block<():int>) {}
[export]
def main() {let value=computation(InvalidLoop()) {while(false) {}}; print("{value}")}
