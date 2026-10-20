options gen2
require ../lib/derive.das
require daslib/rtti
require strings

// A type outside derive can opt in with an ordinary overload.
struct ExternalClone {values:array<int>;fail:bool}
var custom_calls=0
def derive_clone(value:ExternalClone) : ExternalClone {
    custom_calls++
    var result:ExternalClone
    result.values <- _::derive_clone(value.values)
    result.fail=value.fail
    if(value.fail) {
        // A custom clone owns cleanup of its own unfinished result.
        delete result
        panic("custom clone failed")
    }
    return <- result
}
var default_calls=0
def default_values() : array<int> {
    var result:array<int>
    default_calls++
    result <- [7,8]
    return <- result
}
[derive(debug=false,equality=false,hash=false,clone=true)]
struct CustomEnvelope {
    prefix:array<int> = default_values()
    values:array<ExternalClone>
}
[derive(debug=false,equality=false,hash=false,clone=true)]
struct CustomFixed {
    prefix:array<int> = default_values()
    values:ExternalClone[2]
}
variant CustomAction {empty;data:ExternalClone}
[derive(debug=false,equality=false,hash=false,clone=true)]
struct CustomOptional {
    prefix:array<int> = default_values()
    value:$Option<ExternalClone>
}
[derive(debug=false,equality=false,hash=false,clone=true)]
struct CustomPatch {
    prefix:array<int> = default_values()
    value:$JsonField<ExternalClone>
}
[derive(debug=false,equality=false,hash=false,clone=true)]
struct CustomVariant {
    prefix:array<int> = default_values()
    value:CustomAction
}
def external(value:int;fail:bool=false) : ExternalClone {
    var result:ExternalClone
    result.values |> push(value)
    result.fail=fail
    return <- result
}
def check() {
    var inscope source=default<CustomEnvelope>
    var item <- external(1)
    source.values |> emplace(item)
    item <- external(2)
    source.values |> emplace(item)
    custom_calls=0
    let defaultsBefore=default_calls
    var inscope copied <- derive_clone(source)
    verify(custom_calls==2 && default_calls==defaultsBefore)
    copied.values[0].values[0]=99
    copied.prefix[0]=88
    verify(source.values[0].values[0]==1 && source.prefix[0]==7)
    source.values[1].fail=true
    let before=heap_bytes_allocated()
    var caught=false
    try {var inscope unused <- derive_clone(source)} recover {
        caught=true
        verify(find(this_context().last_exception,"custom clone failed")>=0)
    }
    verify(caught && heap_bytes_allocated()==before)
    verify(length(source.values)==2 && source.values[1].values[0]==2)
    var inscope fixed=default<CustomFixed>
    fixed.values[0] <- external(1)
    fixed.values[1] <- external(2,true)
    let beforeFixed=heap_bytes_allocated()
    caught=false
    try {var inscope unused <- derive_clone(fixed)} recover {caught=true}
    verify(caught && heap_bytes_allocated()==beforeFixed && fixed.values[0].values[0]==1)
    var inscope optional=default<CustomOptional>
    item <- external(3,true)
    optional.value <- move_some(item)
    let beforeOptional=heap_bytes_allocated()
    caught=false
    try {var inscope unused <- derive_clone(optional)} recover {caught=true}
    verify(caught && heap_bytes_allocated()==beforeOptional && (optional.value as some).values[0]==3)
    var inscope patch=default<CustomPatch>
    item <- external(4,true)
    patch.value <- json_move_present(item)
    let beforePatch=heap_bytes_allocated()
    caught=false
    try {var inscope unused <- derive_clone(patch)} recover {caught=true}
    verify(caught && heap_bytes_allocated()==beforePatch && (patch.value as present).values[0]==4)
    var inscope variantValue=default<CustomVariant>
    variantValue.value <- CustomAction(data <- external(5,true))
    let beforeVariant=heap_bytes_allocated()
    caught=false
    try {var inscope unused <- derive_clone(variantValue)} recover {caught=true}
    verify(caught && heap_bytes_allocated()==beforeVariant && (variantValue.value as data).values[0]==5)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive clone exception and ownership checks OK\n")
}
