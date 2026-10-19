options gen2
options max_infer_passes=1024
module websocket_echo public
require ../lib/reactivex_async_sequence.das public
require ../../computation_expressions/lib/computation_macro.das
require ../../computation_expressions/lib/task_hv.das public

// A fresh connection belongs to each stream/subscription, not the descriptor.
// AsyncSequence bind returns Task payloads as data, so Result is checked here.
def websocket_echo_stream(url:string;count:int) {
    return <- computation(AsyncSequenceBuilder(type<string>)) {
        var socket & = hv_websocket() |> use_resource
        let connected=ws_connect(socket,url) |> bind
        if(connected is error) {panic(connected as error)}
        for(i in range(count)) {
            let sent=ws_send_text(socket,"message {i}") |> bind
            if(sent is error) {panic(sent as error)}
            let received=ws_receive_text(socket) |> bind
            if(received is error) {panic(received as error)}
            yield received as ok
            task_delay_ms(10) |> bind
        }
    }
}
def rx_echo_messages(url:string;count:int;clock:RxScheduler) {
    if(count<1) {panic("echo count must be positive")}
    var endpoint=string(url)
    return <- rx_from_async_sequence(@ capture(copy(endpoint),copy(count)) () {
        return <- websocket_echo_stream(endpoint,count)
    },clock)
}
