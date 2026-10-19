options gen2
options max_infer_passes=1024
require ../support/glfw_ui.das
require daslib/rtti

def key(code:int;action:int=int(GLFW_PRESS)) {glfw_post_key(rx_ui_window(),code,0,action,0)}
def checks() {
    rx_ui_open(true,10)
    verify(rx_ui_snapshot().health==100 && rx_ui_snapshot().updates==1 && rx_ui_snapshot().callbacks==1)
    key(int(GLFW_KEY_DOWN),int(GLFW_RELEASE))
    verify(rx_ui_snapshot().health==100)
    key(int(GLFW_KEY_DOWN));key(int(GLFW_KEY_DOWN),int(GLFW_REPEAT))
    verify(rx_ui_snapshot().health==50 && rx_ui_snapshot().updates==3)
    key(int(GLFW_KEY_R));key(int(GLFW_KEY_UP))
    verify(rx_ui_snapshot().health==100 && rx_ui_snapshot().updates==4)
    key(int(GLFW_KEY_ESCAPE),int(GLFW_RELEASE))
    verify(!rx_ui_snapshot().stopped)
    key(int(GLFW_KEY_ESCAPE))
    verify(rx_ui_snapshot().stopped && rx_ui_snapshot().subscriptions==0)
    key(int(GLFW_KEY_DOWN))
    verify(rx_ui_snapshot().health==100)
    verify(rx_ui_frame(10l) && rx_ui_snapshot().callbacks==0)
    let before=rx_ui_snapshot().ticks
    verify(rx_ui_frame(20l) && rx_ui_snapshot().ticks>before)
    glfwSetWindowShouldClose(rx_ui_window(),1)
    verify(!rx_ui_frame(21l))
    rx_ui_close();rx_ui_close()
    verify(!rx_ui_snapshot().window_live && rx_ui_snapshot().callbacks==0 && rx_ui_snapshot().pending==0)
    // Closing an active window must also unsubscribe its live input graph.
    rx_ui_open(true,10)
    verify(rx_ui_snapshot().subscriptions==2)
    rx_ui_close()
    verify(rx_ui_snapshot().subscriptions==0 && rx_ui_snapshot().callbacks==0)
}
[export]
def main() {
    try {
        checks()
        let before=heap_bytes_allocated()
        for(i in range(3)) {checks();verify(heap_bytes_allocated()==before)}
    } recover {let message="{this_context().last_exception}";rx_ui_close();panic(message)}
    print("ReactiveX GLFW integration checks OK\n")
}
