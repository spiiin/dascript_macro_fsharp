options gen2
require ../lib/computation_macro.das
require ../lib/async_sequence_builder.das
[export]
def main() {var inscope stream <- computation(AsyncSequenceBuilder()) {return 42}}
