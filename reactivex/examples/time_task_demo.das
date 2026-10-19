options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex_task.das
require ../../computation_expressions/lib/computation_macro.das
var actions:typedecl(rx_subject(type<string>))
var output=""
def wait_for_action() {
    return <- computation(TaskResultBuilder(type<string>)) {
        let action=rx_first_task(actions) |> bind
        return "user action: {action}"
    }
}

def lookup(query:string) {
    return <- computation(TaskResultBuilder(type<string>)) {
        task_delay_ms(20) |> bind
        return "answer: {query}"
    }
}
[export]
def main() {
    var inscope clock <- rx_virtual_scheduler()
    var inscope input <- rx_subject(type<string>)
    var clockView <- rx_scheduler_clone(clock)
    var inscope answers <- rx_clone(input) |> rx_debounce(5,clock) |> rx_switch_map(@ capture(<-clockView) (query:string) {
        return <- rx_from_task_result(@ capture(copy(query)) () {return <- lookup(query)},clockView) |> rx_timeout(40,clockView)
    } finally {delete clockView})
    var inscope subscription <- rx_subscribe(answers,@(text:string) {output=text;print("{text}\n")},
        @(message:string) {print("error: {message}\n")},@(){print("done\n")})
    rx_subject_next(input,"d")
    rx_advance_to(clock,3)
    rx_subject_next(input,"da")
    rx_advance_to(clock,8) // first request starts, then is superseded below.
    rx_advance_to(clock,10)
    rx_subject_next(input,"daScript")
    rx_advance_to(clock,15) // cancels previous Task, starts the replacement.
    rx_advance_to(clock,35) // only "answer: daScript" is delivered.
    rx_subject_complete(input)
    verify(output=="answer: daScript" && rx_is_closed(subscription) && rx_pending_count(clock)==0)

    actions <- rx_subject(type<string>)
    var inscope wait <- wait_for_action()
    verify(task_poll(wait)==TaskStatus.Waiting)
    rx_subject_next(actions,"confirm")
    verify(task_poll(wait)==TaskStatus.Succeeded)
    let result=task_value(wait)
    verify(result is ok)
    print("{result as ok}\n")
    delete actions
    print("ReactiveX time/Task demo OK\n")
}
