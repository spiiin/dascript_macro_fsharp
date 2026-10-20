options gen2
require ../examples/enum_variant_model.das
require daslib/rtti
require strings
struct OpaquePayload {values:array<int>}
var read_count=0
var write_count=0
var fail_read=false
var fail_write=false
def derive_json_decode(node:JsonValue?;var value:OpaquePayload;path:string;var errors:array<ValidationIssue>) {
    value.values <- [1,2,3]
    read_count++
    if(fail_read && read_count==2) {panic("variant decode failed")}
}
def derive_json_encode(value:OpaquePayload) : JsonValue? {
    write_count++
    if(fail_write && write_count==2) {panic("variant encode failed")}
    return JV(length(value.values))
}
variant OpaqueCommand {empty;one:OpaquePayload;many:array<OpaquePayload>}
variant ArrayFirst {items:array<int>;idle;role:CharacterRole}
[derive(json=true,validate=true)]
struct Carrier {action:GameCommand=default<GameCommand>}
def check() {
    fail_read=false;fail_write=false;read_count=0;sum_hook_throws=false
    var inscope owner <- derive_from_json("\{\"case\":\"items\",\"value\":[1,2,3]\}",type<ArrayFirst>,"action",true)
    verify(owner.ok && length(owner.value as items)==3)
    var inscope copy <- derive_from_json(derive_to_json(owner.value),type<ArrayFirst>,"action",true)
    verify(copy.ok && derive_equal(owner.value,copy.value))
    var parseError:string
    var node=read_json("\{\"case\":\"role\",\"value\":\"Rogue\"\}",parseError)
    var inscope errors:array<ValidationIssue>
    derive_json_read(node,owner.value,"action",errors,true);delete_json(node)
    verify(length(errors)==0 && owner.value as role==CharacterRole.Rogue && length(copy.value as items)==3)
    node=read_json("\{\"case\":\"idle\"\}",parseError)
    derive_json_read(node,owner.value,"action",errors,true);delete_json(node)
    verify(owner.value is idle)
    // Every owning selected payload is stored in the result before user code runs.
    let baseline=heap_bytes_allocated()
    fail_read=true;read_count=0
    var caught=false
    try {var inscope ignored <- derive_from_json("\{\"case\":\"many\",\"value\":[1,2]\}",type<OpaqueCommand>,"action",true)} recover {
        caught=true;verify(find(this_context().last_exception,"variant decode failed")>=0)
    }
    verify(caught && heap_bytes_allocated()==baseline)
    fail_read=false;read_count=0
    var inscope opaque <- derive_from_json("\{\"case\":\"many\",\"value\":[1,2]\}",type<OpaqueCommand>,"action",true)
    verify(opaque.ok && length(opaque.value as many)==2)
    let withOpaque=heap_bytes_allocated()
    fail_write=true;write_count=0;caught=false
    try {let ignored=derive_to_json(opaque.value)} recover {caught=true}
    verify(caught && heap_bytes_allocated()==withOpaque)
    fail_write=false;sum_hook_throws=true;caught=false
    try {var inscope ignored <- derive_from_json("\{\"action\":\{\"case\":\"move\",\"value\":\{\"x\":1,\"y\":2,\"values\":[1,2]\}\}\}",type<Carrier>)} recover {
        caught=true;verify(find(this_context().last_exception,"sum validation failed")>=0)
    }
    verify(caught && heap_bytes_allocated()==withOpaque)
    sum_hook_throws=false
    var inscope badEnum <- derive_from_json("\"NoRole\"",type<CharacterRole>)
    verify(!badEnum.ok && badEnum.value==CharacterRole.Warrior)
    let enumBaseline=heap_bytes_allocated()
    var invalid=unsafe(reinterpret<CharacterRole>(99))
    caught=false
    try {let ignored=derive_to_json(invalid)} recover {caught=true}
    verify(caught && heap_bytes_allocated()==enumBaseline)
    var inscope optional <- derive_from_json("\"Mage\"",type<$Option<CharacterRole>>)
    var inscope enumArray <- derive_from_json("[\"Mage\",\"Rogue\"]",type<array<CharacterRole>>)
    var inscope presence <- derive_from_json("\"Rogue\"",type<$JsonField<CharacterRole>>)
    verify(optional.ok && optional.value as some==CharacterRole.Mage && enumArray.ok && enumArray.value[1]==CharacterRole.Rogue && presence.ok && presence.value as present==CharacterRole.Rogue)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive JSON enum variant ownership checks OK\n")
}
