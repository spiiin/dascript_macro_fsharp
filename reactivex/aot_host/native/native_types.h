#pragma once
namespace rx_native_aot {
inline void * managedEntry(bool destroy) {
    auto module=das::Module::require("dashv");
    auto annotation=module ? module->findAnnotation("HttpRequest") : nullptr;
    auto type=static_cast<das::TypeAnnotation*>(annotation);
    void *fn=type ? (destroy ? type->jitGetDelete() : type->jitGetNew()) : nullptr;
    if(!fn) throw std::runtime_error("Missing SDK HttpRequest allocator");
    return fn;
}
}
namespace das {
// The SDK dashv_boost AOT library also emits with_http_request. Its native
// allocation must stay in the original module; no libhv implementation is linked.
template<> struct das_new_handle<HttpRequest,false> {
    static HttpRequest *make(Context *ctx) {
        static auto call=reinterpret_cast<void*(*)(Context*)>(rx_native_aot::managedEntry(false));
        return static_cast<HttpRequest*>(call(ctx));
    }
};
template<> struct das_delete_handle<HttpRequest*> {
    static void clear(Context *ctx,HttpRequest *&ptr) {
        static auto call=reinterpret_cast<void(*)(void*,Context*)>(rx_native_aot::managedEntry(true));
        call(ptr,ctx);ptr=nullptr;
    }
};
}
