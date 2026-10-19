options gen2
options max_infer_passes=1024
require ../support/glfw_ui.das
require daslib/fio
require daslib/jobque_boost
require daslib/rtti

[export]
def main() {
    let smoke=get_env_variable("RX_GLFW_SMOKE")=="1"
    try {
        rx_ui_open(smoke,smoke ? 10 : 250)
        print("Up/Down: change health; R: reset; Esc: stop UI stream. Background continues until the window closes.\n")
        let started=glfwGetTime()
        while(true) {
            let now=int64((glfwGetTime()-started)*double(1000))
            if(smoke && now>=100l) {glfwSetWindowShouldClose(rx_ui_window(),1)}
            if(!rx_ui_frame(now)) {break}
            sleep(5u)
        }
        if(smoke) {verify(rx_ui_snapshot().ticks>0)}
    } recover {let message="{this_context().last_exception}";rx_ui_close();panic(message)}
    rx_ui_close()
    let closed=rx_ui_snapshot()
    verify(!closed.window_live && closed.callbacks==0 && closed.subscriptions==0 && closed.pending==0)
    print("ReactiveX GLFW UI demo OK\n")
}
