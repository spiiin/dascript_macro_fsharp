options gen2
require lazy_native_provider
typedef Missing = provided_type("schemas/native", "MissingDependency")
[export]
def main() { var value = default<Missing>; print("{value}\n") }
