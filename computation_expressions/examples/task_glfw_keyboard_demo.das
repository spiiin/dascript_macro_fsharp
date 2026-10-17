options gen2
require ../support/task_glfw_keyboard.das
require daslib/fio
require daslib/strings_convert
require daslib/rtti
require daslib/jobque_boost

[export]
def main() {
    let timeout=get_env_variable("CE_GLFW_TIMEOUT_MS")
    let timeout_ms=empty(timeout) ? 15000 : to_int(timeout)
    let smoke=get_env_variable("CE_GLFW_SMOKE")=="1"
    if(timeout_ms<1 || timeout_ms>600000) {panic("CE_GLFW_TIMEOUT_MS must be between 1 and 600000")}
    try {
        glfw_keyboard_open(smoke,int64(timeout_ms),smoke ? 10 : 500)
        print("Focus the GLFW window and type. Enter submits, Esc cancels, F2 retries. Close the window to exit.\n")
        print("Input, status and the independent background counter are shown in the window title.\n")
        let started=glfwGetTime()
        while(true) {
            let now_ms=int64((glfwGetTime()-started)*double(1000))
            if(smoke && now_ms>=100l) {glfwSetWindowShouldClose(glfw_keyboard_window(),1)}
            if(!glfw_keyboard_frame(now_ms)) {break}
            sleep(5u)
        }
        if(smoke) {verify(glfw_keyboard_snapshot().ticks>0)}
    } recover {
        let message="{this_context().last_exception}"
        glfw_keyboard_close()
        panic(message)
    }
    glfw_keyboard_close()
    let closed=glfw_keyboard_snapshot()
    verify(!closed.window_live && closed.callbacks==0 && closed.subscriptions==0)
    let stats=task_event_stats()
    verify(stats.sources==0 && stats.waits==0 && stats.subscriptions==0)
    print("Task GLFW keyboard demo OK\n")
}
