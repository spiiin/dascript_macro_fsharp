options gen2
require ../lib/task_events.das
[export]
def main() {var inscope events <- task_event_source(type<int?>)}
