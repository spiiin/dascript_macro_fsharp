options gen2
options max_infer_passes=1024
options stack=262144
require ../support/websocket_echo.das
require daslib/fio
require daslib/strings_convert
require daslib/jobque_boost
require daslib/rtti
require strings
var received=0
var completed=0
var errors=0
var text=""
var message=""
var now=0l
var started:int64
var port=0
var markers=""
def tick(clock:RxScheduler) {
    verify(get_time_usec(started)<15000000)
    now++;rx_tick(clock,now);sleep(1u)
}
def drive(clock:RxScheduler;sub:RxSubscription) {while(!rx_is_closed(sub)) {tick(clock)}}
def seen(clock:RxScheduler;path:string) {while(!fexist("{markers}/{path}")) {tick(clock)}}
def balanced(clock:RxScheduler) {
    let stats=hv_websocket_stats()
    verify(stats.active==0 && stats.active_clients==0 && stats.active_operations==0)
    verify(rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0)
}
def checks(round:int) {
    for(mode in range(11)) {
        received=0;completed=0;errors=0;text="";message="";now=0l;started=ref_time_ticks()
        var inscope clock <- rx_scheduler()
        var inscope stop <- rx_subject(type<int>)
        let handshake=mode==1 || mode==8
        let waiting=mode==2 || mode==3 || mode==7 || mode==9 || mode==10
        let path=handshake ? "handshake_rx_{mode}_{round}" : waiting ? "silent_rx_{mode}_{round}" : mode==5 ? "binary" : "echo_rx_{mode}_{round}"
        var inscope source <- rx_echo_messages("ws://127.0.0.1:{port}/{path}",3,clock) |> rx_timeout(100000,clock) |> rx_take(mode==4 ? 1 : 10) |> rx_take_until(rx_clone(stop))
        var inscope sub <- rx_subscribe(source,@ capture(copy(mode)) (value:string) {
            received++;text+="{value};"
            if(mode==6) {panic("consumer failure")}
        },@(e:string) {errors++;message=string(e)},@() {completed++})
        var caught=false
        try {
            if(handshake || waiting) {
                seen(clock,handshake ? path : "received_{path}")
                verify(!rx_is_closed(sub))
                if(mode==1 || mode==2) {rx_subject_next(stop,0)}
                elif(mode==3 || mode==8) {rx_tick(clock,100000l)}
                elif(mode==9) {rx_unsubscribe(sub)}
                elif(mode==10) {delete sub}
                else {rx_scheduler_close(clock)}
            }
            drive(clock,sub)
        } recover {caught=true;verify(starts_with("{this_context().last_exception}","consumer failure"))}
        verify(caught==(mode==6) && rx_is_closed(sub) && rx_subscriber_count(stop)==0)
        if(mode==0) {verify(received==3 && completed==1 && errors==0 && text=="message 0;message 1;message 2;")}
        elif(mode==1 || mode==2) {verify(received==0 && completed==1 && errors==0)}
        elif(mode==4) {verify(received==1 && completed==1 && errors==0)}
        elif(mode==6) {verify(received==1 && completed==0 && errors==0)}
        elif(mode==9 || mode==10) {verify(received==0 && completed==0 && errors==0)}
        else {verify(received==0 && completed==0 && errors==1 && !empty(message))}
        if(mode==3 || mode==8) {verify(message=="rx timeout")}
        if(mode==5) {verify(find(message,"binary")>=0)}
        if(mode==7) {verify(message=="rx scheduler closed")}
        balanced(clock)
        // Check the remote peer, not only local counters.
        started=ref_time_ticks()
        while(!fexist("{markers}/closed_{path}")) {verify(get_time_usec(started)<15000000);sleep(1u)}
    }
    // Cancelling a cold subscription must not start a native client at all.
    {
        var inscope clock <- rx_scheduler()
        var inscope stop <- rx_subject(type<int>)
        let created=hv_websocket_stats().created
        var inscope source <- rx_echo_messages("ws://127.0.0.1:{port}/echo_never",3,clock) |> rx_take_until(rx_clone(stop))
        var inscope sub <- rx_subscribe(source,@(s:string) {panic("cold cancellation emitted")},@(s:string) {panic(s)},@() {})
        rx_subject_next(stop,0)
        verify(rx_is_closed(sub) && hv_websocket_stats().created==created)
        balanced(clock)
    }
}
[export]
def main() {
    port=to_int(get_env_variable("CE_HV_PORT"));markers=get_env_variable("CE_HV_MARKERS")
    checks(0)
    let before=heap_bytes_allocated()
    checks(1)
    verify(heap_bytes_allocated()==before)
    print("ReactiveX WebSocket integration checks OK\n")
}
