options gen2
require ../support/task_glfw_keyboard.das
require daslib/rtti

def key(code:int;action:int=int(GLFW_PRESS)) {glfw_post_key(glfw_keyboard_window(),code,0,action,0)}
def character(cp:uint) {glfw_post_char(glfw_keyboard_window(),cp)}
def closed() {
    let state=glfw_keyboard_snapshot()
    verify(!state.window_live && state.callbacks==0 && state.subscriptions==0)
    let stats=task_event_stats()
    verify(stats.sources==0 && stats.waits==0 && stats.subscriptions==0)
}
def success() {
    glfw_keyboard_open(true,1000l,10)
    verify(glfw_keyboard_snapshot().subscriptions==1 && glfw_keyboard_snapshot().callbacks==2)
    character(uint('a'));character(0x1F642u)
    verify(glfw_keyboard_snapshot().text=="a🙂")
    key(int(GLFW_KEY_BACKSPACE),int(GLFW_REPEAT))
    character(0x20ACu)
    verify(glfw_keyboard_snapshot().text=="a€")
    key(int(GLFW_KEY_BACKSPACE),int(GLFW_REPEAT))
    character(0x416u) // Cyrillic Ж, after removing one entire astral character.
    key(int(GLFW_KEY_ENTER),int(GLFW_REPEAT)) // Repeated Enter must not submit.
    verify(glfw_keyboard_frame(10l))
    verify(glfw_keyboard_snapshot().text=="aЖ" && glfw_keyboard_snapshot().waiting)
    key(int(GLFW_KEY_ENTER))
    verify(glfw_keyboard_snapshot().continued==0) // No inline continuation in callbacks.
    verify(glfw_keyboard_frame(20l))
    let state=glfw_keyboard_snapshot()
    verify(state.reader==TaskStatus.Succeeded && state.result=="aЖ" && state.continued==1)
    verify(!state.waiting && state.subscriptions==0 && !state.timed_out)
    character(uint('x'))
    verify(glfw_keyboard_frame(30l))
    verify(glfw_keyboard_snapshot().ticks>state.ticks && glfw_keyboard_snapshot().text=="aЖ")
    glfw_keyboard_close();closed()
}
def cancellation_and_retry() {
    glfw_keyboard_open(true,1000l,10)
    key(int(GLFW_KEY_ESCAPE),int(GLFW_RELEASE))
    verify(glfw_keyboard_frame(10l) && glfw_keyboard_snapshot().waiting)
    key(int(GLFW_KEY_ESCAPE))
    verify(glfw_keyboard_frame(11l))
    let cancelled=glfw_keyboard_snapshot()
    verify(cancelled.reader==TaskStatus.Cancelled && !cancelled.timed_out && cancelled.continued==0)
    verify(cancelled.subscriptions==0)
    verify(glfw_keyboard_frame(21l) && glfw_keyboard_snapshot().ticks>cancelled.ticks)
    key(int(GLFW_KEY_F2))
    verify(glfw_keyboard_frame(22l) && glfw_keyboard_snapshot().subscriptions==1)
    character(uint('r'));key(int(GLFW_KEY_ENTER))
    verify(glfw_keyboard_frame(23l))
    verify(glfw_keyboard_snapshot().result=="r" && glfw_keyboard_snapshot().continued==1)
    glfw_keyboard_close();closed()
}
def timeout_and_retry() {
    glfw_keyboard_open(true,5l,10)
    character(uint('p'))
    key(int(GLFW_KEY_F2)) // Cannot reset an active wait's deadline.
    verify(glfw_keyboard_frame(4l) && glfw_keyboard_snapshot().waiting)
    verify(glfw_keyboard_frame(5l))
    let expired=glfw_keyboard_snapshot()
    verify(expired.reader==TaskStatus.Cancelled && expired.timed_out && expired.continued==0)
    verify(expired.subscriptions==0)
    verify(glfw_keyboard_frame(15l) && glfw_keyboard_snapshot().ticks>expired.ticks)
    key(int(GLFW_KEY_F2))
    verify(glfw_keyboard_frame(100l))
    verify(glfw_keyboard_snapshot().waiting && !glfw_keyboard_snapshot().timed_out)
    verify(glfw_keyboard_frame(104l) && glfw_keyboard_snapshot().waiting)
    verify(glfw_keyboard_frame(105l) && glfw_keyboard_snapshot().timed_out)
    glfw_keyboard_close();closed()
}
def editing_and_close() {
    glfw_keyboard_open(true,1000l,10)
    character(0xD800u);character(0x110000u);character(0u)
    verify(glfw_keyboard_snapshot().text=="")
    for(i in range(70)) {character(uint('a'))}
    verify(length(glfw_keyboard_snapshot().text)==64)
    key(int(GLFW_KEY_BACKSPACE))
    character(0x1F642u)
    verify(length(glfw_keyboard_snapshot().text)==67)
    verify(glfw_keyboard_frame(10l))
    glfwSetWindowShouldClose(glfw_keyboard_window(),1)
    verify(!glfw_keyboard_frame(11l))
    glfw_keyboard_close()
    let state=glfw_keyboard_snapshot()
    verify(state.reader==TaskStatus.Cancelled && state.background==TaskStatus.Cancelled && state.continued==0)
    closed();glfw_keyboard_close();closed()
}
def queued_event_cancel() {
    glfw_keyboard_open(true,1000l,10)
    character(uint('q'));key(int(GLFW_KEY_ENTER));key(int(GLFW_KEY_ESCAPE))
    verify(glfw_keyboard_snapshot().continued==0)
    verify(glfw_keyboard_frame(10l))
    let cancelled=glfw_keyboard_snapshot()
    verify(cancelled.reader==TaskStatus.Cancelled && cancelled.continued==0 && cancelled.subscriptions==0)
    key(int(GLFW_KEY_F2))
    verify(glfw_keyboard_frame(11l) && glfw_keyboard_snapshot().waiting && glfw_keyboard_snapshot().text=="")
    key(int(GLFW_KEY_ENTER)) // An empty string is also a valid action, not a lost event.
    verify(glfw_keyboard_frame(12l))
    verify(glfw_keyboard_snapshot().reader==TaskStatus.Succeeded && glfw_keyboard_snapshot().result=="")
    verify(glfw_keyboard_snapshot().continued==1 && glfw_keyboard_snapshot().subscriptions==0)
    glfw_keyboard_close();closed()
}
def checks() {success();cancellation_and_retry();timeout_and_retry();editing_and_close();queued_event_cancel()}
[export]
def main() {
    try {
        checks()
        let before=heap_bytes_allocated()
        for(i in range(3)) {checks();verify(heap_bytes_allocated()==before)}
    } recover {
        let message="{this_context().last_exception}"
        glfw_keyboard_close()
        panic(message)
    }
    print("Task GLFW keyboard checks OK\n")
}
