options gen2
require ../lib/derive.das
require daslib/rtti
require strings

struct ExternalDiff {id:int;values:array<int>}
var fail_diff=false
var fail_debug=false
var calls=0
def derive_debug(value:ExternalDiff) : string {
    if(fail_debug) {panic("diff snapshot failed")}
    return "External({value.id})"
}
def derive_diff_into(before,after:ExternalDiff;path:string;var changes:array<DiffChange>) {
    calls++
    if(before.id!=after.id) {diff_add(changes,diff_path(path,"id"),"changed","{before.id}","{after.id}")}
    if(fail_diff) {panic("custom diff failed")}
    _::derive_diff_into(before.values,after.values,diff_path(path,"values"),changes)
}
[derive(diff=true,equality=false,hash=false)]
struct DiffEnvelope {prefix:int;values:array<ExternalDiff>}
variant ExternalDiffVariant {idle;data:ExternalDiff}

def check() {
    var inscope before:DiffEnvelope
    var inscope after:DiffEnvelope
    after.prefix=1
    var value:ExternalDiff
    value.values <- [1,2];before.values |> emplace(value)
    value.id=2;value.values <- [3,4];after.values |> emplace(value)
    calls=0
    var inscope normal <- derive_diff(before,after,"root")
    verify(calls==1 && length(normal)==4 && normal[1].path=="root.values[0].id" && normal[3].path=="root.values[0].values[1]")
    fail_diff=true
    let baseline=heap_bytes_allocated()
    var caught=false
    try {var inscope ignored <- derive_diff(before,after,"root")} recover {
        caught=true;verify(find(this_context().last_exception,"custom diff failed")>=0)
    }
    verify(caught && heap_bytes_allocated()==baseline && before.values[0].values[0]==1 && after.values[0].values[0]==3)
    // The append API retains already appended changes when a user hook throws.
    var inscope partial:array<DiffChange>
    diff_add(partial,"manual","changed","old","new")
    caught=false
    try {derive_diff_into(before,after,"root",partial)} recover {caught=true}
    verify(caught && length(partial)==3 && partial[0].path=="manual" && partial[2].path=="root.values[0].id")
    fail_diff=false
    // Snapshot formatting can also throw after earlier changes were collected.
    value.id=3;value.values <- [5];after.values |> emplace(value)
    fail_debug=true
    let beforeSnapshot=heap_bytes_allocated()
    caught=false
    try {var inscope ignored <- derive_diff(before,after)} recover {
        caught=true;verify(find(this_context().last_exception,"diff snapshot failed")>=0)
    }
    verify(caught && heap_bytes_allocated()==beforeSnapshot)
    var inscope av <- ExternalDiffVariant(idle)
    value.id=4;value.values <- [6]
    var inscope bv <- ExternalDiffVariant(data <- value)
    let beforeVariant=heap_bytes_allocated()
    caught=false
    try {var inscope ignored <- derive_diff(av,bv)} recover {caught=true}
    verify(caught && heap_bytes_allocated()==beforeVariant && (bv as data).values[0]==6)
    fail_debug=false
    var inscope whole <- derive_diff(av,bv)
    verify(length(whole)==1 && whole[0].kind=="case" && whole[0].after=="data(External(4))")
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive diff custom and ownership checks OK\n")
}
