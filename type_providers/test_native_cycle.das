options gen2
require lazy_native_provider
typedef Cycle = provided_type("schemas/native", "CycleA")
[export]
def main() { var value = default<Cycle>; print("{value}\n") }
