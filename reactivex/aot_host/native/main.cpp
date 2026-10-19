#include "daScript/daScript.h"
#include "daScript/misc/sysos.h"
#include <iostream>
#include "daScript/ast/dyn_modules.h"
#include <stdexcept>
using namespace das;
struct HostContext:Context {
    using Context::Context;
    void to_out(const LineInfo *,int,const char *message) override {std::cout << message;}
};
int run(int argc, char **argv) {
    if(argc < 3) {std::cerr << "Usage: " << argv[0] << " SDK_ROOT SCRIPT...\n";return 2;}
    setDasRoot(argv[1]);
    NEED_ALL_DEFAULT_MODULES;
    NEED_MODULE(Module_JobQue);
    daScriptEnvironment::ensure();
    TextPrinter initialization;
    auto files=make_smart<FsFileAccess>();
    // Explicit module folders keep this host independent of other SDK plugins.
    if(!require_dynamic_modules(files,getDasRoot()+"/.rx-no-scan","",
        vector<string>{getDasRoot()+"/modules/dasGlfw",getDasRoot()+"/modules/dasHV"},initialization)) {
        std::cerr << "Native module initialization failed: " << initialization.str();
        return 3;
    }
    Module::Initialize();
    int failures=0;
    for(int i=2;i<argc;i++) {
        TextPrinter out;
        ModuleGroup group;
        auto access=make_smart<FsFileAccess>();
        CodeOfPolicies policies;
        policies.aot=true;
        policies.aot_module=true;
        policies.threadlock_context=false;
        policies.tune_frozen=true;
        policies.rtti=true;
        policies.persistent_heap=true;
        policies.fail_on_no_aot=true;
        auto program=compileDaScript(argv[i],access,out,group,policies);
        if(program->failed()) {
            for(auto &err:program->errors) out << reportError(err.at,err.what,err.extra,err.fixme,err.cerr);
            std::cerr << out.str();failures++;continue;
        }
        HostContext context(program->getContextStackSize(),true);
        if(!program->simulate(context,out)) {
            std::cerr << "Simulation failed: " << out.str();
            for(auto &err:program->errors) std::cerr << reportError(err.at,err.what,err.extra,err.fixme,err.cerr);
            for(auto &err:program->aotErrors) std::cerr << reportError(err.at,err.what,err.extra,err.fixme,err.cerr);
            if(auto error=context.getException()) std::cerr << error;
            failures++;continue;
        }
        auto main=context.findFunction("main");
        if(!main || !main->aot) {std::cerr << "Main is NOT AOT-linked: " << argv[i] << "\n";failures++;continue;}
        context.evalWithCatch(main,nullptr);
        if(auto error=context.getException()) {std::cerr << error << "\n";failures++;continue;}
        std::cout << "AOT RUNTIME PASS: " << argv[i] << " (main->aot=yes, strict linking)\n";
    }
    Module::Shutdown();
    return failures ? 1:0;
}

int main(int argc,char **argv) {
    try {return run(argc,argv);}
    catch(const std::exception &error) {std::cerr << "Native AOT host: " << error.what() << "\n";return 3;}
}
