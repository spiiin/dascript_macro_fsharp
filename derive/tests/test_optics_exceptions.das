options gen2
require ../lib/derive.das
require daslib/rtti
require strings

struct OpticExternal {values:array<int>;fail:bool}
var clone_calls=0
var default_calls=0
var effects=0
def derive_clone(value:OpticExternal) : OpticExternal {
    clone_calls++
    var result:OpticExternal
    result.values <- derive_clone(value.values)
    result.fail=value.fail
    if(value.fail) {delete result;panic("optic clone failed")}
    return <- result
}
def initial_values() : array<int> {default_calls++;return <- [4,5]}
[derive(debug=false,equality=false,hash=false,clone=true)]
struct OpticEnvelope {
    prefix:array<int> = initial_values()
    item:OpticExternal
    count:int
}
def external(fail:bool=false) : OpticExternal {
    var result:OpticExternal
    result.values <- [1,2,3]
    result.fail=fail
    return <- result
}
def envelope(fail:bool=false) : OpticEnvelope {
    var result=default<OpticEnvelope>
    result.item <- external(fail)
    return <- result
}
def failing_replacement() : array<int> {panic("replacement failed");return <- default<array<int>>}

def check() {
    var inscope source <- envelope()
    let defaults=default_calls
    clone_calls=0
    var inscope updated <- source |> optic_set("count",1) |> optic_set("count",2)
    verify(clone_calls==1 && default_calls==defaults && source.count==0 && updated.count==2)
    var inscope bad <- external(true)
    let baseline=heap_bytes_allocated()
    for(mode in range(7)) {
        var caught=false
        try {
            if(mode==0) {
                source.item.fail=true
                var inscope unused <- source |> optic_set("count",3)
            } elif(mode==1) {
                var inscope unused <- source |> optic_set("item",bad)
            } elif(mode==2) {
                var inscope unused <- source |> optic_over("count") <| $(value:int) : int {effects++;panic("modifier failed");return value}
            } elif(mode==3) {
                var inscope unused <- source |> optic_set("count",4) |> optic_over("item.values") <| $(values:array<int>) : array<int> {
                    effects++;panic("modifier failed");return <- default<array<int>>
                }
            } elif(mode==4) {
                var inscope unused <- envelope(true) |> optic_get("item")
            } elif(mode==5) {
                var inscope unused <- source |> optic_set("item.values",failing_replacement())
            } else {
                var inscope unused <- envelope() |> optic_over("count") <| $(value:int) : int {effects++;panic("modifier failed");return value}
            }
        } recover {caught=true}
        source.item.fail=false
        verify(caught && heap_bytes_allocated()==baseline)
        verify(source.count==0 && source.item.values[0]==1 && source.prefix[0]==4)
    }
    // Effects in callbacks are external to the copied value and are not rolled back.
    verify(effects>=3)
    // Manual clone overloads can be used for a root without derive.
    var inscope manual <- source.item |> optic_set("fail",true)
    verify(manual.fail && !source.item.fail)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive optics exception and ownership checks OK\n")
}
