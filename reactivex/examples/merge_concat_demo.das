options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
var received=""
var completed=0
var stages=0

def show(source:auto;left,right:auto;merged:bool) {
    received=""
    let before=completed
    var inscope sub <- rx_subscribe(source,@(value:string) {received+="{value};";print("  {value}\n")},@(message:string) {panic(message)},@(){completed++;print("  complete\n")})
    rx_subject_next(left,"keyboard: move")
    rx_subject_next(right,"server: update 1")
    rx_subject_next(left,"keyboard: attack")
    rx_subject_complete(left)
    rx_subject_next(right,"server: update 2")
    rx_subject_complete(right)
    verify(completed==before+1 && rx_is_closed(sub))
    verify(rx_subscriber_count(left)==0 && rx_subscriber_count(right)==0)
    verify(received==(merged ? "keyboard: move;server: update 1;keyboard: attack;server: update 2;" : "keyboard: move;keyboard: attack;server: update 2;"))
}
[export]
def main() {
    {
        print("merge: keyboard and server are both subscribed\n")
        var inscope keyboard <- rx_subject(type<string>)
        var inscope server <- rx_subject(type<string>)
        var inscope events <- rx_clone(keyboard) |> rx_merge(rx_clone(server))
        show(events,keyboard,server,true)
    }
    {
        print("concat: server is subscribed after keyboard completes\n")
        var inscope keyboard <- rx_subject(type<string>)
        var inscope server <- rx_subject(type<string>)
        var inscope events <- rx_clone(keyboard) |> rx_concat(rx_clone(server))
        show(events,keyboard,server,false)
    }
    // Delay the second producer itself, rather than missing early hot events.
    {
        print("concat with a deferred second stage\n")
        var inscope tasks <- rx_range(1,2) |> rx_concat(rx_defer(@() {stages++;return <- rx_range(10,2)}))
        verify(stages==0)
        var inscope sub <- rx_subscribe(tasks,@(n:int) {print("  stage value: {n}\n")},@(message:string) {panic(message)},@(){})
        verify(stages==1 && rx_is_closed(sub))
    }
    print("ReactiveX merge/concat demo OK\n")
}
