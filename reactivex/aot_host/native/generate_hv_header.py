"""Generate SDK 0.6.5-RC2 native forwarding declarations (no script fallback)."""
import re
from pathlib import Path
root=Path(__file__).resolve().parent
source=(root/'upstream_aot_hv_065.h').read_text()
start=source.index('namespace das {')
prelude=source[:start]
prelude=prelude.replace('#include "daScript/misc/handle_registry.h"','#include "native_binding.h"')
result=[prelude,'namespace das {\n    struct WebSocketAdmission;\n']
body=re.sub(r'//[^\n]*','',source[start+len('namespace das {'):]).strip().rstrip('}')
for prototype in body.split(';'):
    prototype=' '.join(prototype.split())
    if not prototype or prototype=='struct WebSocketAdmission':continue
    match=re.fullmatch(r'(.+?)\s+(\w+)\s*\((.*)\)',prototype)
    if not match:raise ValueError(prototype)
    ret,name,args=match.groups()
    parts=[];begin=0;depth=0
    for i,c in enumerate(args):
        if c=='<':depth+=1
        elif c=='>':depth-=1
        elif c==',' and depth==0:parts.append(args[begin:i]);begin=i+1
    if args.strip():parts.append(args[begin:])
    names=[];types=[]
    for part in parts:
        arg=re.fullmatch(r'(.*?)\b(\w+)\s*',part.strip())
        if not arg:raise ValueError(part)
        types.append(arg[1].strip());names.append(arg[2])
    result.append(f'inline {ret} {name}({args}) {{\n'
                  f'    using Fn={ret}(*)({",".join(types)});\n'
                  f'    static auto call=rx_native_aot::resolve<Fn>("{name}");\n'
                  f'    return call({",".join(names)});\n}}\n')
result.append('}\n')
# Never instantiate a private HandleRegistry in the executable.
for native,annotation in [('hv::WebSocketClient','WebSocketClient'),('hv::WebSocketServer','WebSocketServer'),('hv::WebSocketChannel','WebSocketChannel'),('das::WebSocketAdmission','WebSocketAdmission')]:
    for operation in ['is_alive','release']:
        result.append(f'namespace das {{ template<> inline bool das_handle_{operation}<{native}>(Handle<{native}> h) {{\n'
                      f'    using Fn=bool(*)(Handle<{native}>);\n'
                      f'    static auto call=rx_native_aot::resolve<Fn>("das_handle_{operation}","{annotation}");\n'
                      f'    return call(h);\n}} }}\n')
(root/'aot_hv.h').write_text(''.join(result),encoding='utf-8')
with (root/'aot_hv.h').open('a',encoding='utf-8') as out:out.write('\n#include \"native_types.h\"\n')
