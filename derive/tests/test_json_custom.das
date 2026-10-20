options gen2
require ../examples/json_game_model.das
require daslib/rtti
require strings
struct External {text:string}
var throw_decode=false
var throw_encode=false
var decode_calls=0
var encode_calls=0
// Both overloads are in the model's module, called through normal dispatch.
def derive_json_encode(value:External) : JsonValue? {
    encode_calls++
    if(throw_encode && encode_calls==2) {panic("custom JSON encode failed")}
    return JV(value.text)
}
def derive_json_decode(node:JsonValue?;var value:External;path:string;var errors:array<ValidationIssue>) {
    decode_calls++
    if(throw_decode && decode_calls==2) {panic("custom JSON decode failed")}
    derive_json_decode(node,value.text,path,errors)
}
[derive(debug=false,equality=false,hash=false,json=true)]
struct Packet {items:array<External>}
[derive(json=true,validate=true)]
struct Small {
    @validate_min=0
    @validate_max=10
    signed:int8
    @validate_max=100
    unsigned:uint16
}
def check() {
    throw_decode=false;throw_encode=false;decode_calls=0;json_hook_throws=false
    var inscope packet <- derive_from_json("\{\"items\":[\"one\",\"two\"]\}",type<Packet>)
    verify(packet.ok && packet.value.items[1].text=="two")
    var inscope roundtrip <- derive_from_json(derive_to_json(packet.value),type<Packet>)
    verify(roundtrip.ok && roundtrip.value.items[0].text=="one")
    // Exception after allocating one child: encoder and decoder free partial ownership.
    let baseline=heap_bytes_allocated()
    throw_encode=true;encode_calls=0
    var caught=false
    try {let ignored=derive_to_json(packet.value)} recover {
        caught=true;verify(find(this_context().last_exception,"custom JSON encode failed")>=0)
    }
    verify(caught && heap_bytes_allocated()==baseline && length(packet.value.items)==2)
    throw_decode=true;decode_calls=0;caught=false
    try {var inscope ignored <- derive_from_json("\{\"items\":[\"one\",\"two\"]\}",type<Packet>)} recover {
        caught=true;verify(find(this_context().last_exception,"custom JSON decode failed")>=0)
    }
    verify(caught && heap_bytes_allocated()==baseline)
    throw_decode=false;throw_encode=false
    json_hook_throws=true;caught=false
    try {var inscope ignored <- derive_from_json(json_game_text(),type<JsonGame>)} recover {
        caught=true;verify(find(this_context().last_exception,"JSON validation hook failed")>=0)
    }
    verify(caught && heap_bytes_allocated()==baseline)
    json_hook_throws=false
    var inscope small <- derive_from_json("\{\"signed\":-1,\"unsigned\":101\}",type<Small>)
    verify(!small.ok && length(small.errors)==2 && small.errors[0].code=="min")
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive JSON custom and ownership checks OK\n")
}
