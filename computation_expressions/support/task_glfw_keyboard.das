options gen2
module task_glfw_keyboard public
require ../lib/computation_macro.das
require ../lib/task_scheduler.das public
require ../lib/task_events.das public
require glfw public
require daslib/rtti
require strings

var private demo_window:GLFWwindow?
var private glfw_live=false
var private events_live=false
var private scheduler_live=false
var private reader_live=false
var private background_live=false
var private events:typedecl(task_event_source(type<string>))
var private scheduler:typedecl(task_scheduler(type<variant<ok:string;error:string>>))
var private token:CancellationToken
var private reader:TaskId
var private background:TaskId
var private codepoints:array<uint>
var private text=""
var private result_text=""
var private status_text=""
var private last_title=""
var private waiting=false
var private submitted=false
var private restart_requested=false
var private timeout_ms=15000l
var private heartbeat_ms=500
var private ticks=0
var private continued=0
var private reader_status=TaskStatus.Created
var private background_status=TaskStatus.Created
var private timed_out=false
var private callbacks=0
var private key_handler:lambda<(w:GLFWwindow const?;key:int;scan:int;action:int;mods:int):void>
var private char_handler:lambda<(w:GLFWwindow const?;codepoint:uint):void>

def private encode_utf8(cp:uint) {
    if(cp<0x80u) {return to_char(int(cp))}
    if(cp<0x800u) {return to_char(int(0xC0u|(cp>>6u)))+to_char(int(0x80u|(cp&0x3Fu)))}
    if(cp<0x10000u) {return to_char(int(0xE0u|(cp>>12u)))+to_char(int(0x80u|((cp>>6u)&0x3Fu)))+to_char(int(0x80u|(cp&0x3Fu)))}
    return to_char(int(0xF0u|(cp>>18u)))+to_char(int(0x80u|((cp>>12u)&0x3Fu)))+to_char(int(0x80u|((cp>>6u)&0x3Fu)))+to_char(int(0x80u|(cp&0x3Fu)))
}
def private rebuild_text() {
    text=""
    for(cp in codepoints) {text+=encode_utf8(cp)}
}
def private on_char(cp:uint) {
    if(!waiting || submitted || cp<32u || cp==127u || cp>0x10FFFFu || (cp>=0xD800u && cp<=0xDFFFu)) {return}
    if(length(codepoints)>=64) {return}
    codepoints |> push(cp)
    rebuild_text()
}
def private on_key(key,action:int) {
    if(action==int(GLFW_PRESS) && key==int(GLFW_KEY_F2) && !waiting) {restart_requested=true;return}
    if(!waiting) {return}
    if(key==int(GLFW_KEY_ESCAPE) && action==int(GLFW_PRESS)) {cancellation_cancel(token);return}
    if(submitted) {return}
    if(key==int(GLFW_KEY_ENTER) && action==int(GLFW_PRESS)) {
        submitted=true
        task_event_emit(events,text)
    } elif(key==int(GLFW_KEY_BACKSPACE) && (action==int(GLFW_PRESS) || action==int(GLFW_REPEAT))) {
        if(!empty(codepoints)) {codepoints |> erase(length(codepoints)-1);rebuild_text()}
    }
}
def private read_input() {
    return <- computation(TaskResultBuilder(type<string>)) {
        let value=task_wait_event(events) |> bind
        continued++
        return value
    }
}
def private heartbeat() {
    return <- computation(TaskResultBuilder(type<string>)) {
        while(true) {
            task_delay_ms(heartbeat_ms) |> bind
            ticks++
        }
        return "background finished"
    }
}
def private start_reader() {
    delete token
    token <- cancellation_token()
    delete codepoints
    text="";result_text="";submitted=false;timed_out=false
    status_text="Type text, Enter submits, Esc cancels"
    reader=task_spawn(scheduler,task_with_cancellation(read_input(),token),TaskTimeout(after_ms=timeout_ms))
    reader_live=true;waiting=true
}
def private update_status() {
    reader_status=task_status(scheduler,reader)
    background_status=task_status(scheduler,background)
    if(waiting && reader_status!=TaskStatus.Waiting && reader_status!=TaskStatus.Created) {
        waiting=false
        timed_out=task_timed_out(scheduler,reader)
        if(reader_status==TaskStatus.Cancelled) {status_text=timed_out ? "Timed out - F2 retries" : "Cancelled - F2 retries"}
        elif(reader_status==TaskStatus.Failed) {panic(task_error(scheduler,reader))}
        else {
            let result=task_value(scheduler,reader)
            if(result is ok) {result_text=result as ok;status_text="Accepted: {result_text} - F2 retries"}
            else {status_text="Error: {result as error} - F2 retries"}
        }
        verify(task_event_subscriber_count(events)==0)
        print("{status_text}; background ticks={ticks}\n")
    }
    let title="Task keyboard | background: {ticks} | {status_text} | input: {text}"
    if(title!=last_title) {glfwSetWindowTitle(demo_window,title);last_title=title}
}

def glfw_keyboard_close() {
    // Remove native references before deleting lambdas or their referenced state.
    if(demo_window!=null) {glfw_chain_clear(demo_window)}
    unsafe {delete key_handler;delete char_handler}
    // Explicit reset keeps repeated close safe in both interpreter and JIT.
    key_handler <- default<typedecl(key_handler)>
    char_handler <- default<typedecl(char_handler)>
    callbacks=0
    if(scheduler_live) {
        task_scheduler_close(scheduler)
        if(reader_live) {reader_status=task_status(scheduler,reader)}
        if(background_live) {background_status=task_status(scheduler,background)}
        delete scheduler;scheduler_live=false
    }
    delete token
    if(events_live) {delete events;events_live=false}
    delete codepoints
    waiting=false;restart_requested=false;reader_live=false;background_live=false
    if(demo_window!=null) {glfwDestroyWindow(demo_window);demo_window=null}
    if(glfw_live) {glfwTerminate();glfw_live=false}
    text="";result_text="";status_text="";last_title=""
}

def glfw_keyboard_open(hidden:bool=false;timeout:int64=15000l;interval:int=500) {
    if(glfw_live || scheduler_live || events_live) {panic("GLFW keyboard demo is already open")}
    if(timeout<1 || interval<1) {panic("GLFW keyboard timeout and heartbeat must be positive")}
    timeout_ms=timeout;heartbeat_ms=interval;ticks=0;continued=0;last_title=""
    try {
        if(glfwInit()==0) {panic("glfwInit failed: a desktop/windowing session is required")}
        glfw_live=true
        glfwDefaultWindowHints()
        // No OpenGL context, renderer or GPU driver is needed. The title is the UI.
        glfwWindowHint(int(GLFW_CLIENT_API),int(GLFW_NO_API))
        glfwWindowHint(int(GLFW_VISIBLE),hidden ? 0 : 1)
        if(hidden) {glfwWindowHint(int(GLFW_FOCUSED),0)}
        demo_window=glfwCreateWindow(1100,100,"Task keyboard",null,null)
        if(demo_window==null) {panic("glfwCreateWindow failed")}
        events <- task_event_source(type<string>);events_live=true
        scheduler <- task_scheduler(type<variant<ok:string;error:string>>);scheduler_live=true
        start_reader()
        background=task_spawn(scheduler,heartbeat());background_live=true
        // Native callbacks do not own script lambdas. Keep them until chain_clear.
        key_handler=@(w:GLFWwindow const?;key,scan,action,mods:int) {on_key(key,action)}
        char_handler=@(w:GLFWwindow const?;cp:uint) {on_char(cp)}
        glfw_chain_add_key(demo_window,key_handler)
        glfw_chain_add_char(demo_window,char_handler)
        callbacks=2
        task_tick(scheduler,0)
        update_status()
    } recover {
        let message="{this_context().last_exception}"
        glfw_keyboard_close()
        panic(message)
    }
}

def glfw_keyboard_frame(now_ms:int64) : bool {
    if(demo_window==null) {return false}
    glfwPollEvents()
    if(glfwWindowShouldClose(demo_window)!=0) {return false}
    task_tick(scheduler,now_ms)
    if(restart_requested) {
        restart_requested=false
        // Advance the scheduler clock before spawning, so a retry gets a fresh deadline.
        reader_live=false
        task_prune(scheduler)
        start_reader()
        task_tick(scheduler,now_ms)
    }
    update_status()
    return true
}
def glfw_keyboard_window() {return demo_window}
def glfw_keyboard_snapshot() {
    return (waiting=waiting,text=text,result=result_text,ticks=ticks,continued=continued,
        reader=reader_status,background=background_status,timed_out=timed_out,
        callbacks=callbacks,window_live=demo_window!=null,
        subscriptions=events_live ? task_event_subscriber_count(events) : 0)
}
