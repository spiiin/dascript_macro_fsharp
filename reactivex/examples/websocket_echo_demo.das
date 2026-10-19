options gen2
options max_infer_passes=1024
options stack=262144
require ../support/websocket_echo.das
require daslib/fio
require daslib/strings_convert
require daslib/jobque_boost
require daslib/rtti
var received=0
var completed=0
var failed=false
var ticks=0
var cancel:typedecl(rx_subject(type<int>))

[export]
def main() {
    let configured=get_env_variable("RX_WS_URL")
    let url=empty(configured) ? "ws://127.0.0.1:{to_int(get_env_variable("CE_HV_PORT"))}/echo_rx_demo" : configured
    var inscope clock <- rx_scheduler()
    cancel <- rx_subject(type<int>)
    var inscope stream <- rx_echo_messages(url,1000,clock) |> rx_timeout(5000,clock) |> rx_take_until(rx_clone(cancel))
    var inscope subscription <- rx_subscribe(stream,@(text:string) {
        print("WebSocket: {text}\n");received++
        if(received==3) {rx_subject_next(cancel,0)} // Cancel while the producer is delivering.
    },@(message:string) {failed=true;print("WebSocket error: {message}\n")},@() {completed++})
    var inscope pulse <- rx_interval(10,clock)
    var inscope background <- rx_subscribe(pulse,@(n:int64) {ticks++},@(e:string) {panic(e)},@() {})
    let started=ref_time_ticks()
    while(!rx_is_closed(subscription)) {
        verify(get_time_usec(started)<15000000)
        rx_tick(clock,int64(get_time_usec(started)/1000));sleep(1u)
    }
    rx_unsubscribe(background)
    verify(rx_pending_count(clock)==0 && rx_subscriber_count(cancel)==0)
    let stats=hv_websocket_stats()
    verify(stats.active==0 && stats.active_clients==0 && stats.active_operations==0)
    delete cancel
    verify(!failed && received==3 && completed==1 && ticks>0)
    print("ReactiveX WebSocket demo OK: cancelled after three messages; background ticks={ticks}\n")
}
