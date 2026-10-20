options gen2
require ../lib/computation_macro.das
require ../lib/task_scheduler.das
require ../lib/task_events.das

// A UI event bus lives outside the suspended computation.
var actions:typedecl(task_event_source(type<string>))

def on_confirm_clicked() {task_event_emit(actions,"confirm")}
// A business choice completes normally; closing the UI cancels its Task below.
def on_cancel_clicked() {task_event_emit(actions,"cancel")}

def confirmation_dialog() {
    return <- computation(TaskResultBuilder(type<string>)) {
        let action=task_wait_event(actions) |> bind
        return action=="confirm" ? "Purchase confirmed" : "Purchase declined"
    }
}
[export]
def main() {
    actions <- task_event_source(type<string>)
    var inscope token <- cancellation_token()
    var inscope scheduler <- task_scheduler(type<$Result<string;string>>)
    let dialog=task_spawn(scheduler,task_with_cancellation(confirmation_dialog(),token),TaskTimeout(after_ms=5000))
    verify(task_tick(scheduler,0)==1)
    verify(task_event_subscriber_count(actions)==1)

    // Simulate a UI callback between frames. No continuation runs in emit.
    on_confirm_clicked()
    verify(task_status(scheduler,dialog)==TaskStatus.Waiting)
    verify(task_tick(scheduler,16)==0)
    let result=task_value(scheduler,dialog)
    verify(result is ok && result as ok=="Purchase confirmed")
    verify(task_event_subscriber_count(actions)==0)
    print("{result as ok}\n")

    let abandoned=task_spawn(scheduler,task_with_cancellation(confirmation_dialog(),token))
    verify(task_tick(scheduler,32)==1)
    // Closing the UI cancels its pending work.
    cancellation_cancel(token)
    verify(task_tick(scheduler,48)==0 && task_status(scheduler,abandoned)==TaskStatus.Cancelled)
    verify(task_event_subscriber_count(actions)==0)

    let expired=task_spawn(scheduler,confirmation_dialog(),TaskTimeout(after_ms=5))
    verify(task_tick(scheduler,49)==1)
    verify(task_tick(scheduler,53)==0 && task_timed_out(scheduler,expired))
    verify(task_event_subscriber_count(actions)==0)
    delete actions
    let stats=task_event_stats()
    verify(stats.sources==0 && stats.waits==0 && stats.subscriptions==0)
    print("Task event demo OK\n")
}
