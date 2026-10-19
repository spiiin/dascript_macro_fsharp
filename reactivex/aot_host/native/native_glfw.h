#pragma once
#include "native_binding.h"
namespace das {
// Missing from the SDK's aot_dasGLFW.h; use the same native event dispatcher.
inline void DasGlfw_PollEvents() {
    static auto call=rx_native_aot::resolve<void(*)()>("DasGlfw_PollEvents",nullptr,"glfw");
    call();
}
}
