options gen2
require ../lib/derive.das
require daslib/rtti
struct BuilderExternal {items:array<int>}
var builder_fail_clone=false
var builder_fail_validation=false
var builder_defaults=0
var builder_fail_default=false

def builder_throw_default() : int {if(builder_fail_default) {panic("builder default failed")};return 42}
def builder_default() : array<int> {builder_defaults++;return <- [10,20]}
def derive_clone(value:BuilderExternal) : BuilderExternal {
    if(builder_fail_clone) {panic("builder clone failed")}
    var result:BuilderExternal
    result.items <- _::derive_clone(value.items)
    return <- result
}
def derive_validate_into(value:BuilderExternal;path:string;var errors:array<ValidationIssue>) {
    if(builder_fail_validation) {
        validation_add(errors,path,"before panic","custom")
        panic("builder validation failed")
    }
}
[derive(debug=false,equality=false,hash=false,builder=true,validate=true)]
struct BuilderEnvelope {
    owned:array<int> = builder_default()
    @builder_required
    external:BuilderExternal
    last:int = builder_throw_default()
}
def check() {
    var inscope draft <- derive_builder(type<BuilderEnvelope>)
    let calls=builder_defaults
    var inscope missing <- derive_build(draft)
    verify(!missing.ok && builder_defaults==calls)
    var inscope external:BuilderExternal
    external.items <- [1,2]
    draft |> builder_external(external)
    external.items[0]=7
    verify(draft.data.external.items[0]==1)
    let baseline=heap_bytes_allocated()
    for(mode in range(2)) {
        builder_fail_clone=mode==0;builder_fail_validation=mode==1
        var caught=false
        try {var inscope unused <- derive_build(draft)} recover {caught=true}
        verify(caught && heap_bytes_allocated()==baseline && draft.data.external.items[0]==1)
        builder_fail_clone=false;builder_fail_validation=false
    }
    builder_fail_default=true
    var caughtDefault=false
    try {var inscope unused <- derive_build(draft)} recover {caughtDefault=true}
    verify(caughtDefault && heap_bytes_allocated()==baseline && draft.data.external.items[0]==1)
    builder_fail_default=false
    builder_fail_clone=true
    var caught=false
    try {draft |> builder_external(external)} recover {caught=true}
    verify(caught && heap_bytes_allocated()==baseline && draft.data.external.items[0]==1)
    builder_fail_clone=false
    var inscope result <- derive_build(draft)
    verify(result.ok && (result.value as some).owned[0]==10)
    verify(builder_defaults==calls+4)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive builder exception checks OK\n")
}
