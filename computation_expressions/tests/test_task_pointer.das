options gen2
require ../lib/task_builder.das
[export]
def main() {var pointer:int?;var inscope task <- task_after_polls(0,pointer)}
