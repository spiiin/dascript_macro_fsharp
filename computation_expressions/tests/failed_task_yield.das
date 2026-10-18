options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das
[export]
def main() {var inscope task <- computation(TaskBuilder(type<int>)) {yield 42;return 0}}
