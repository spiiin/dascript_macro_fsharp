options gen2
options max_infer_passes=1024
module glfw_ui public
require ../lib/reactivex.das public
require glfw public

struct RxUiAction {delta:int;reset:bool}
var private window:GLFWwindow?
var private glfw_live=false
var private graph_live=false
var private actions:typedecl(rx_subject(type<RxUiAction>))
var private stop:typedecl(rx_subject(type<int>))
var private clock:RxScheduler
var private interaction:RxSubscription
var private background:RxSubscription
var private keys:lambda<(w:GLFWwindow const?;key:int;scan:int;action:int;mods:int):void>
var private health=100
var private updates=0
var private ticks=0
var private stopped=false
var private callbacks=0

def private title() {
    if(window!=null) {glfwSetWindowTitle(window,"ReactiveX | health: {health} | updates: {updates} | background: {ticks} | {stopped ? "Stopped" : "Up/Down: health, R: reset, Esc: stop"}")}
}
def private detach() {
    if(window!=null) {glfw_chain_clear(window)}
    unsafe {delete keys}
    keys <- default<typedecl(keys)>
    callbacks=0
}
def rx_ui_close() {
    // Native chains borrow the lambda. Detach before deleting it or its graph.
    detach()
    delete interaction;delete background
    if(graph_live) {
        rx_scheduler_close(clock);delete clock
        delete actions;delete stop;graph_live=false
    }
    if(window!=null) {glfwDestroyWindow(window);window=null}
    if(glfw_live) {glfwTerminate();glfw_live=false}
}
def private on_key(key,action:int) {
    if(stopped || (action!=int(GLFW_PRESS) && action!=int(GLFW_REPEAT))) {return}
    if(key==int(GLFW_KEY_ESCAPE) && action==int(GLFW_PRESS)) {rx_subject_next(stop,0)}
    elif(key==int(GLFW_KEY_UP)) {rx_subject_next(actions,RxUiAction(delta=25))}
    elif(key==int(GLFW_KEY_DOWN)) {rx_subject_next(actions,RxUiAction(delta=-25))}
    elif(key==int(GLFW_KEY_R) && action==int(GLFW_PRESS)) {rx_subject_next(actions,RxUiAction(reset=true))}
}
def rx_ui_open(hidden:bool=false;heartbeat_ms:int=250) {
    if(glfw_live || graph_live) {panic("ReactiveX UI is already open")}
    if(heartbeat_ms<=0) {panic("heartbeat must be positive")}
    health=100;updates=0;ticks=0;stopped=false
    try {
        if(glfwInit()==0) {panic("glfwInit failed: a desktop session is required")}
        glfw_live=true
        glfwDefaultWindowHints()
        glfwWindowHint(int(GLFW_CLIENT_API),int(GLFW_NO_API))
        glfwWindowHint(int(GLFW_VISIBLE),hidden ? 0 : 1)
        if(hidden) {glfwWindowHint(int(GLFW_FOCUSED),0)}
        window=glfwCreateWindow(1050,120,"ReactiveX",null,null)
        if(window==null) {panic("glfwCreateWindow failed")}
        actions <- rx_subject(type<RxUiAction>)
        stop <- rx_subject(type<int>)
        clock <- rx_scheduler();graph_live=true
        var inscope states <- rx_clone(actions) |> rx_scan(100,@(hp:int;event:RxUiAction) {
            let next=event.reset ? 100 : hp+event.delta
            return next<0 ? 0 : next>100 ? 100 : next
        }) |> rx_start_with(100) |> rx_distinct_until_changed() |> rx_take_until(rx_clone(stop))
        interaction <- rx_subscribe(states,@(hp:int) {health=hp;updates++;title()},@(e:string) {panic(e)},@() {stopped=true;title()})
        var inscope pulse <- rx_interval(heartbeat_ms,clock)
        background <- rx_subscribe(pulse,@(n:int64) {ticks++;title()},@(e:string) {panic(e)},@() {})
        keys=@(w:GLFWwindow const?;key,scan,action,mods:int) {on_key(key,action)}
        glfw_chain_add_key(window,keys);callbacks=1
    } recover {
        let message="{this_context().last_exception}"
        rx_ui_close();panic(message)
    }
}
def rx_ui_frame(now_ms:int64) : bool {
    if(window==null) {return false}
    glfwPollEvents()
    // Do not delete a native callback's own lambda while it is executing.
    if(stopped && callbacks!=0) {detach()}
    if(glfwWindowShouldClose(window)!=0) {return false}
    rx_tick(clock,now_ms)
    return true
}
def rx_ui_window() {return window}
def rx_ui_snapshot() {
    return (health=health,updates=updates,ticks=ticks,stopped=stopped,callbacks=callbacks,window_live=window!=null,
        subscriptions=graph_live ? rx_subscriber_count(actions)+rx_subscriber_count(stop) : 0,
        pending=graph_live ? rx_pending_count(clock) : 0)
}
