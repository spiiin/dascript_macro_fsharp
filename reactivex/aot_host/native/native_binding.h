#pragma once
#ifndef RX_NATIVE_BINDING_H
#define RX_NATIVE_BINDING_H
#include "daScript/ast/ast.h"
#include "daScript/ast/ast_handle.h"
#include "daScript/simulate/jit_abi.h"
#include <stdexcept>

namespace rx_native_aot {
// These are native entry points, not interpreted script functions. The SDK
// wraps value handles as uint64 (not the MSVC struct-return ABI).
template<class Fn> struct Entry;
template<class Ret,class... Args> struct Entry<Ret(*)(Args...)> {
    void *address;
    Ret operator()(Args... args) const {
        using Native=typename das::ResolvedWrapType<Ret>::rettype(*)(das::JitSideT_t<Args>...);
        auto call=reinterpret_cast<Native>(address);
        if constexpr(std::is_void_v<Ret>) {call(static_cast<das::JitSideT_t<Args>>(args)...);}
        else {return static_cast<Ret>(call(static_cast<das::JitSideT_t<Args>>(args)...));}
    }
};
template<class Fn> Entry<Fn> resolve(const char *cppName,const char *handleType=nullptr,const char *moduleName="dashv") {
    auto module=das::Module::require(moduleName);
    void *address=nullptr;
    unsigned matches=0;
    if(module) module->functions.foreach([&](const das::FunctionPtr &fn) {
        if(!fn->builtIn) return;
        auto builtin=static_cast<das::BuiltInFunction*>(fn);
        if(builtin->cppName!=cppName) return;
        if(handleType) {
            if(fn->arguments.empty()) return;
            auto type=fn->arguments[0]->type;
            if(!type->annotation || type->annotation->name!=handleType) return;
        }
        if(builtin->interopFn || builtin->policyBased) throw std::runtime_error("Unsupported native ABI");
        address=builtin->getBuiltinAddress();
        ++matches;
    });
    if(matches!=1 || !address) throw std::runtime_error(das::string("Missing or ambiguous native entry: ")+cppName);
    return Entry<Fn>{address};
}
}
#endif
