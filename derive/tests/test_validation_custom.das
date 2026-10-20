options gen2
require ../lib/derive.das
require daslib/rtti
require strings
var calls=0
var should_throw=false
[derive(validate=true,check="check_record")]
struct Record {
    @validate_min=1
    count:int
    @validate_non_empty
    names:array<string>
}
def check_record(value:Record;path:string;var errors:array<ValidationIssue>) {
    calls++
    verify(length(errors)>=2 && errors[length(errors)-2].path==validation_path(path,"count"))
    validation_add(errors,validation_path(path,"names"),"business rule","business")
    if(should_throw) {panic("validation hook failed")}
}
// Manual overload is also usable for a type outside derive's supported set.
struct External {text:string}
def derive_validate_into(value:External;path:string;var errors:array<ValidationIssue>) {
    if(value.text!="ok") {validation_add(errors,path,"external rejected","external")}
}
[derive(debug=false,equality=false,hash=false,validate=true)]
struct Envelope {external:External}
def check() {
    var inscope value:Record
    calls=0;should_throw=false
    var inscope issues <- derive_validate(value,"record")
    verify(calls==1 && length(issues)==3 && issues[2].code=="business")
    should_throw=true
    var caught=false
    let before=heap_bytes_allocated()
    try {
        var inscope ignored <- derive_validate(value,"record")
    } recover {caught=true;verify(find(this_context().last_exception,"validation hook failed")>=0)}
    verify(caught && calls==2 && heap_bytes_allocated()==before)
    // A failed validation leaves the source owned and usable.
    value.names |> push("still alive")
    verify(length(value.names)==1)
    var inscope external <- derive_validate(Envelope(external=External(text="bad")),"root")
    verify(length(external)==1 && external[0].path=="root.external")
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive validation custom checks OK\n")
}
