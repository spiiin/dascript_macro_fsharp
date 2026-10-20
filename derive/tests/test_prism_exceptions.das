options gen2
require ../lib/derive.das
require daslib/rtti
require strings

struct PrismExternal {values:array<int>;fail:bool}
var clone_calls=0
var default_calls=0
var effects=0
def derive_clone(value:PrismExternal) : PrismExternal {
    clone_calls++
    var result:PrismExternal
    result.values <- derive_clone(value.values)
    result.fail=value.fail
    if(value.fail) {delete result;panic("prism clone failed")}
    return <- result
}
def initial_values() : array<int> {default_calls++;return <- [4,5]}
variant PrismAction {idle;data:PrismExternal;items:array<int>}
[derive(debug=false,equality=false,hash=false,clone=true)]
struct PrismEnvelope {
    prefix:array<int> = initial_values()
    item:$Option<PrismExternal>
    field:$JsonField<PrismExternal>
    action:PrismAction
}
def external(fail:bool=false) : PrismExternal {
    var result:PrismExternal
    result.values <- [1,2,3]
    result.fail=fail
    return <- result
}
def envelope(fail:bool=false) : PrismEnvelope {
    var result=default<PrismEnvelope>
    result.item <- move_some(external(fail))
    result.field <- json_move_present(external())
    result.action <- PrismAction(data <- external())
    return <- result
}
def failing_replacement() : array<int> {panic("replacement failed");return <- default<array<int>>}

def check() {
    var inscope source <- envelope()
    let defaults=default_calls
    clone_calls=0
    var inscope updated <- source |> prism_set("item.some.fail",false) |> prism_set("action.data.fail",false)
    verify(clone_calls==3 && default_calls==defaults)
    var inscope bad <- external(true)
    let baseline=heap_bytes_allocated()
    for(mode in range(8)) {
        var caught=false
        try {
            if(mode==0) {
                (source.item as some).fail=true
                var inscope unused <- source |> prism_over("item.some.values") <| $(values:array<int>) {return <- derive_clone(values)}
            } elif(mode==1) {
                var inscope unused <- source |> prism_set("item.some",bad)
            } elif(mode==2) {
                var inscope unused <- source |> prism_over("item.some.fail") <| $(value:bool) : bool {effects++;panic("modifier failed");return value}
            } elif(mode==3) {
                var inscope unused <- source |> prism_set("item.some.fail",false) |> prism_over("action.data.values") <| $(values:array<int>) : array<int> {
                    effects++;panic("modifier failed");return <- default<array<int>>
                }
            } elif(mode==4) {
                var inscope unused <- envelope(true) |> prism_try_get("item.some")
            } elif(mode==5) {
                var inscope unused <- source |> prism_set("field.present.values",failing_replacement())
            } elif(mode==6) {
                (source.item as some).fail=true
                var inscope unused <- source |> prism_try_get("item.some")
            } else {
                var inscope unused <- envelope() |> prism_over("action.data.fail") <| $(value:bool) : bool {effects++;panic("modifier failed");return value}
            }
        } recover {caught=true}
        (source.item as some).fail=false
        verify(caught && heap_bytes_allocated()==baseline)
        verify((source.item as some).values[0]==1 && source.prefix[0]==4 && (source.field as present).values[0]==1)
    }
    verify(effects>=3)
    // Nonmatching updates suppress throwing callbacks and replacement expressions.
    var inscope absent=default<PrismEnvelope>
    var inscope skipped <- absent |> prism_over("item.some.fail") <| $(value:bool) : bool {panic("must not run");return value}
    var inscope notReplaced <- absent |> prism_set("field.present.values",failing_replacement())
    verify(skipped.item is none && notReplaced.field is missing)
    // An absent owned root is still closed by a failed-preview operation.
    var inscope emptySnapshot <- default<PrismEnvelope> |> prism_try_get("item.some")
    verify(emptySnapshot is none)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive prism exception and ownership checks OK\n")
}
