#pragma once
#include "daScript/misc/platform.h"
#include "daScript/simulate/simulate.h"
#include "daScript/simulate/aot.h"

// SDK 0.6.4 and 0.6.5-RC2 das_try_recover invoke catch before installing last_exception,
// restoring throwBuf and clearing stopFlags. Match the interpreter ordering.
// Forced-include this header in every generated AOT translation unit.
namespace das {
inline void ce_aot_try_recover_064(Context *context,
    const callable<void()> &body, const callable<void()> &handler) {
    auto savedArgs=context->abiArg;
    auto savedCmres=context->abiCMRES;
#if DAS_VERSION >= 605
    auto savedFastCallDepth=context->fastCallDepth;
#endif
    char *ep,*sp;
    context->stack.watermark(ep,sp);
    auto restore=[&]() {
        context->abiArg=savedArgs;
        context->abiCMRES=savedCmres;
#if DAS_VERSION >= 605
        context->fastCallDepth=savedFastCallDepth;
#endif
        context->stack.pop(ep,sp);
        context->stopFlags=0;
        context->last_exception=context->exception;
        context->exception=nullptr;
    };
#if DAS_ENABLE_EXCEPTIONS
    try {body();}
    catch(const dasException &) {restore();handler();}
#else
    jmp_buf jump;
    auto previous=context->throwBuf;
    context->throwBuf=&jump;
    if(!setjmp(jump)) {body();context->throwBuf=previous;}
    else {
        context->throwBuf=previous;
        restore();
        handler();
    }
#endif
}
}
#define das_try_recover ce_aot_try_recover_064
