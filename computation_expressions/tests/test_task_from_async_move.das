options gen2
require ../lib/task_builder.das
require daslib/async_boost
[async]
def owned_values() : array<int> {var values <- [1,2];yield <- values}
[export]
def main() {var inscope task <- task_from_async(owned_values())}
