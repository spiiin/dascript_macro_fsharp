options gen2
require ../lib/derive.das
require daslib/rtti
require strings

struct PatchExternal {id:int;values:array<int>}
var clone_calls=0
var fail_clone_at=0
var fail_equal=false
var fail_validation=false
var fail_apply=false

def derive_clone(value:PatchExternal) : PatchExternal {
    clone_calls++
    var result:PatchExternal
    result.id=value.id;result.values <- _::derive_clone(value.values)
    if(fail_clone_at>0 && clone_calls==fail_clone_at) {
        delete result
        panic("patch custom clone failed")
    }
    return <- result
}
def derive_equal(a,b:PatchExternal) : bool {
    if(fail_equal) {panic("patch equality failed")}
    return a.id==b.id && _::derive_equal(a.values,b.values)
}
def derive_validate_into(value:PatchExternal;path:string;var errors:array<ValidationIssue>) {
    if(fail_validation) {
        validation_add(errors,path,"before validation exception","custom")
        panic("patch validation failed")
    }
    if(value.id<0) {validation_add(errors,validation_path(path,"id"),"negative id","external")}
}
def derive_patch_into(var current:PatchExternal;expected,desired:PatchExternal;path:string;var errors:array<ValidationIssue>) {
    if(fail_apply) {
        validation_add(errors,path,"before custom apply exception","custom")
        panic("patch apply failed")
    }
    derive_patch_replace(current,expected,desired,path,errors)
}
[derive(debug=false,hash=false,clone=true,validate=true,patch=true)]
struct PatchEnvelope {prefix:array<int>;external:PatchExternal;revision:int}

def envelope(id:int) : PatchEnvelope {
    var value:PatchEnvelope
    value.prefix <- [1,2]
    value.external.id=id;value.external.values <- [3,4]
    return <- value
}
def check() {
    var inscope before <- envelope(1)
    var inscope after <- envelope(2)
    after.prefix[0]=7
    // The second snapshot fails after the first snapshot was cloned.
    clone_calls=0;fail_clone_at=2
    let beforeMake=heap_bytes_allocated()
    var caught=false
    try {var inscope unused <- derive_make_patch(before,after)} recover {
        caught=true;verify(find(this_context().last_exception,"patch custom clone failed")>=0)
    }
    verify(caught && heap_bytes_allocated()==beforeMake && before.prefix[0]==1 && after.prefix[0]==7)
    fail_clone_at=0
    var inscope patch <- derive_make_patch(before,after)
    // Candidate cloning, replacement cloning, equality, custom apply, and validation.
    for(mode in range(5)) {
        clone_calls=0
        fail_clone_at=mode<2 ? mode+1 : 0
        fail_equal=mode==2;fail_apply=mode==3;fail_validation=mode==4
        let baseline=heap_bytes_allocated()
        caught=false
        try {var inscope unused <- derive_apply_patch(before,patch,"root")} recover {caught=true}
        verify(caught && heap_bytes_allocated()==baseline)
        verify(before.prefix[0]==1 && before.external.id==1 && before.external.values[0]==3)
        clone_calls=0
        caught=false
        try {var inscope unused <- derive_apply_patch_to(before,patch,"root")} recover {caught=true}
        verify(caught && heap_bytes_allocated()==baseline && before.external.id==1 && before.prefix[0]==1)
        fail_clone_at=0;fail_equal=false;fail_apply=false;fail_validation=false
    }
    // The low-level API is explicitly non-atomic; caller owns partial candidate/errors.
    var inscope candidate <- derive_clone(before)
    var inscope partial:array<ValidationIssue>
    validation_add(partial,"manual","retained")
    fail_apply=true;caught=false
    try {derive_patch_into(candidate,patch.expected,patch.desired,"root",partial)} recover {caught=true}
    fail_apply=false
    verify(caught && length(partial)==2 && partial[0].path=="manual" && partial[1].path=="root.external")
    verify(candidate.prefix[0]==7 && before.prefix[0]==1)
    var inscope successful <- derive_apply_patch(before,patch)
    verify(successful.ok && (successful.value as some).external.id==2)
    (successful.value as some).external.values[0]=99
    verify(before.external.values[0]==3 && patch.desired.external.values[0]==3)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive patch exception and ownership checks OK\n")
}
