options gen2
options max_infer_passes=256
require ../lib/reactivex.das

var health=50
var updates=0
var released=0
struct GameAction {name:string;amount:int}
[export]
def main() {
    var inscope numbers <- rx_range(1,6) |> rx_filter(@(n:int) {return n%2==0}) |> rx_map(@(n:int) {return n*10}) |> rx_take(2)
    // Cold Observable: each subscription starts from the beginning.
    for(run in range(2)) {
        var inscope subscription <- rx_subscribe(numbers,
            @(value:int) {print("number: {value}\n")},
            @(message:string) {panic(message)},
            @() {print("numbers complete\n")})
        verify(rx_is_closed(subscription))
    }
    // Hot Subject: a game/UI callback can push actions as they happen.
    var inscope actions <- rx_subject(type<GameAction>)
    var inscope heals <- rx_clone(actions) |> rx_filter(@(action:GameAction) {return action.name=="heal"}) |> rx_map(@(action:GameAction) {return action.amount}) |> rx_take(2)
    var inscope subscription <- rx_subscribe(heals,
        @(amount:int) {health+=amount;updates++;print("health: {health}\n")},
        @(message:string) {print("error: {message}\n")},
        @() {print("healing complete\n")})
    rx_add_cleanup(subscription,@() {released++;print("healing subscription released\n")})
    rx_subject_next(actions,GameAction(name="move",amount=1))
    rx_subject_next(actions,GameAction(name="heal",amount=10))
    rx_subject_next(actions,GameAction(name="heal",amount=25))
    rx_subject_next(actions,GameAction(name="heal",amount=100))
    verify(health==85 && updates==2 && released==1 && rx_subscriber_count(actions)==0)
    verify(!rx_unsubscribe(subscription)) // already completed by take(2)
    rx_subject_complete(actions)
    print("ReactiveX demo OK\n")
}
