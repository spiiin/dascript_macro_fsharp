options gen2
require ../examples/json_presence_model.das
require daslib/rtti
def default_presence_user() {return <- default<PresenceUser>}
[derive(json=true)]
struct StrictEnvelope {
    user:PresenceUser=default<PresenceUser>
    items:array<PresenceUser>
    fixed:PresenceUser[1]=fixed_array(default_presence_user())
    nullable:$Option<PresenceUser>
    patch:$JsonField<PresenceUser>
}
// Legacy codecs remain usable. A nested tolerant load must not change outer strictness.
struct Legacy {value:int}
def derive_json_encode(value:Legacy) : JsonValue? {return JV(value.value)}
def derive_json_decode(node:JsonValue?;var value:Legacy;path:string;var errors:array<ValidationIssue>) {
    var inscope nested <- derive_from_json("\{\"score\":1,\"values\":[],\"extra\":true\}",type<PresenceDetail>)
    verify(nested.ok)
    derive_json_decode(node,value.value,path,errors)
}
[derive(debug=false,equality=false,hash=false,json=true)]
struct Reentrant {legacy:Legacy;user:PresenceUser=default<PresenceUser>}
struct Transparent {user:PresenceUser=default<PresenceUser>}
def derive_json_encode(value:Transparent) : JsonValue? {return derive_json_encode(value.user)}
def derive_json_read(node:JsonValue?;var value:Transparent;path:string;var errors:array<ValidationIssue>;strict:bool) {
    derive_json_read(node,value.user,path,errors,strict)
}
def check() {
    let user="\{\"displayName\":\"A\",\"nickname\":null,\"z\":0,\"a\":0,\"session\":9,\"name\":\"wrong name\"\}"
    let text="\{\"user\":"+user+",\"items\":["+user+"],\"fixed\":["+user+"],\"nullable\":"+user+",\"patch\":"+user+",\"rootTypo\":true\}"
    var inscope relaxed <- derive_from_json(text,type<StrictEnvelope>,"config")
    verify(relaxed.ok && relaxed.value.fixed[0].session==42)
    presence_hook_calls=0
    var inscope strictResult <- derive_from_json(text,type<StrictEnvelope>,"config",true)
    verify(!strictResult.ok && length(strictResult.errors)==21 && presence_hook_calls==0)
    // Unknown keys sorted within each object; then known fields in declaration order.
    verify(strictResult.errors[0].path=="config.rootTypo" && strictResult.errors[0].code=="json_unknown")
    verify(strictResult.errors[1].path=="config.user.a" && strictResult.errors[4].path=="config.user.z")
    verify(strictResult.errors[5].path=="config.items[0].a" && strictResult.errors[9].path=="config.fixed[0].a")
    verify(strictResult.errors[13].path=="config.nullable.a" && strictResult.errors[17].path=="config.patch.a")
    verify(strictResult.errors[2].path=="config.user.name") // Native name is not the JSON name.
    var inscope combined <- derive_from_json("\{\"displayName\":3,\"unknown\":true\}",type<PresenceUser>,"user",JsonReadLimits(),true)
    verify(length(combined.errors)==3 && combined.errors[0].code=="json_unknown" && combined.errors[1].code=="json_type" && combined.errors[2].code=="json_missing")
    var inscope reentrant <- derive_from_json("\{\"legacy\":7,\"user\":"+user+"\}",type<Reentrant>,"root",true)
    verify(!reentrant.ok && length(reentrant.errors)==4 && reentrant.errors[0].path=="root.user.a")
    var inscope transparent <- derive_from_json(user,type<Transparent>,"opaque",true)
    verify(!transparent.ok && length(transparent.errors)==4 && transparent.errors[0].path=="opaque.a")
    var inscope limited <- derive_from_json(text,type<StrictEnvelope>,"config",JsonReadLimits(max_bytes=4),true)
    verify(!limited.ok && limited.errors[0].code=="json_parse")
    var inscope duplicate <- derive_from_json("\{\"x\":1,\"x\":2\}",type<PresenceUser>,"user",true)
    verify(!duplicate.ok && length(duplicate.errors)==1 && duplicate.errors[0].code=="json_parse")
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive JSON strict checks OK\n")
}
