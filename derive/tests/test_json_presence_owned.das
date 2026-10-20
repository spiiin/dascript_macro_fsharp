options gen2
require ../examples/json_presence_model.das
require daslib/rtti
require strings
[derive(json=true,validate=true)]
struct PresenceOwned {
    first:$Option<PresenceDetail>
    second:$JsonField<PresenceDetail>
}
struct ThrowPayload {values:array<int>}
var throw_payload=false
var payload_calls=0
var encode_payload=false
var encode_calls=0
def derive_json_decode(node:JsonValue?;var value:ThrowPayload;path:string;var errors:array<ValidationIssue>) {
    value.values <- [1,2,3]
    payload_calls++
    if(throw_payload && payload_calls==2) {panic("presence decode failed")}
}
def derive_json_encode(value:ThrowPayload) : JsonValue? {
    encode_calls++
    if(encode_payload && encode_calls==2) {panic("presence encode failed")}
    return JV(length(value.values))
}
[derive(debug=false,equality=false,hash=false,json=true)]
struct Throws {items:array<$Option<ThrowPayload>>;patch:$JsonField<ThrowPayload>}
[derive(json=true)]
struct Defaults {
    @json_required=false
    note:$Option<string> =some("guest")
}
def check() {
    throw_payload=false;encode_payload=false;payload_calls=0;presence_hook_throws=false
    var inscope owned <- derive_from_json("\{\"first\":\{\"score\":1,\"values\":[1,2]\},\"second\":\{\"score\":2,\"values\":[3,4]\}\}",type<PresenceOwned>,"root",true)
    verify(owned.ok)
    var inscope cloned <- derive_from_json(derive_to_json(owned.value),type<PresenceOwned>,"root",true)
    verify(cloned.ok && derive_equal(owned.value,cloned.value) && derive_hash(owned.value)==derive_hash(cloned.value))
    // Reset active owning payloads in-place through the low-level API.
    var node=JVNull()
    var inscope errors:array<ValidationIssue>
    derive_json_read(node,owned.value.first,"first",errors,true)
    derive_json_read(node,owned.value.second,"second",errors,true)
    delete_json(node)
    verify(owned.value.first is none && owned.value.second is null_value && length(errors)==0)
    verify(length((cloned.value.first as some).values)==2) // Independent ownership.
    var inscope absent <- derive_from_json("\{\}",type<Defaults>)
    var inscope explicitNull <- derive_from_json("\{\"note\":null\}",type<Defaults>)
    verify(absent.ok && absent.value.note as some=="guest" && explicitNull.ok && explicitNull.value.note is none)
    var inscope source <- [1,2,3]
    var inscope copied <- json_present(source)
    var inscope moved <- json_move_present(source)
    verify(length(source)==0 && length(copied as present)==3 && length(moved as present)==3)
    var inscope empty <- json_missing(type<array<int>>)
    var inscope nullField <- json_null(type<array<int>>)
    verify(empty is missing && nullField is null_value && !derive_equal(empty,nullField))
    let baseline=heap_bytes_allocated()
    var caught=false
    try {let ignored=derive_to_json(empty)} recover {caught=true}
    verify(caught && heap_bytes_allocated()==baseline)
    throw_payload=true;payload_calls=0;caught=false
    try {var inscope ignored <- derive_from_json("\{\"items\":[1,2],\"patch\":3\}",type<Throws>,"root",true)} recover {
        caught=true;verify(find(this_context().last_exception,"presence decode failed")>=0)
    }
    verify(caught && heap_bytes_allocated()==baseline)
    throw_payload=false
    var inscope payloads <- derive_from_json("\{\"items\":[1,2],\"patch\":3\}",type<Throws>,"root",true)
    verify(payloads.ok)
    let withPayloads=heap_bytes_allocated()
    encode_payload=true;encode_calls=0;caught=false
    try {let ignored=derive_to_json(payloads.value)} recover {caught=true}
    verify(caught && heap_bytes_allocated()==withPayloads)
    encode_payload=false;presence_hook_throws=true;caught=false
    try {var inscope ignored <- derive_from_json("\{\"first\":\{\"score\":1,\"values\":[1,2]\},\"second\":null\}",type<PresenceOwned>)} recover {caught=true}
    verify(caught && heap_bytes_allocated()==withPayloads)
    presence_hook_throws=false
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive JSON presence ownership checks OK\n")
}
