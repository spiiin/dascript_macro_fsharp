options gen2
options max_infer_passes=512
require ../lib/reactivex.das
var trace=""

[export]
def main() {
    var inscope health <- rx_behavior_subject(100)
    var inscope first <- rx_subscribe(health,
        @(hp:int) {print("health: {hp}\n")},@(s:string) {panic(s)},@() {print("health complete\n")})
    rx_subject_next(health,75)
    var inscope late <- rx_subscribe(health,
        @(hp:int) {print("late health: {hp}\n")},@(s:string) {panic(s)},@() {})
    verify(rx_behavior_value(health)==75)
    rx_subject_complete(health)

    var inscope log <- rx_replay_subject(type<string>,2)
    rx_subject_next(log,"started")
    rx_subject_next(log,"connected")
    rx_subject_next(log,"ready") // evicts "started"
    rx_subject_complete(log)
    var inscope history <- rx_subscribe(log,
        @(s:string) {trace+="{s};";print("history: {s}\n")},
        @(s:string) {panic(s)},@() {trace+="done;";print("history complete\n")})
    verify(trace=="connected;ready;done;" && rx_is_closed(history))
    verify(rx_subject_buffered_count(log)==2 && rx_subscriber_count(log)==0)
    print("ReactiveX BehaviorSubject/ReplaySubject demo OK\n")
}
