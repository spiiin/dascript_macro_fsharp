options gen2
require ../examples/json_presence_model.das
require daslib/rtti
require strings

def check() {
    var inscope missing <- derive_from_json("\{\"displayName\":\"Alice\",\"nickname\":null\}",type<PresenceUser>,"user",true)
    verify(missing.ok && missing.value.name=="Alice" && missing.value.nickname is none && missing.value.bio is missing)
    var inscope nul <- derive_from_json("\{\"displayName\":\"Alice\",\"nickname\":null,\"bio\":null\}",type<PresenceUser>,"user",true)
    verify(nul.ok && nul.value.bio is null_value)
    var inscope presentValue <- derive_from_json("\{\"displayName\":\"Alice\",\"nickname\":\"Al\",\"bio\":\"Hello\",\"detail\":\{\"score\":1,\"values\":[1,2]\},\"patch\":\{\"score\":2,\"values\":[3]\}\}",type<PresenceUser>,"user",true)
    verify(presentValue.ok && presentValue.value.nickname is some && presentValue.value.nickname as some=="Al")
    verify(presentValue.value.bio is present && presentValue.value.bio as present=="Hello")
    verify(length((presentValue.value.detail as some).values)==2 && (presentValue.value.patch as present).score==2)
    let missingText=derive_to_json(missing.value)
    let nullText=derive_to_json(nul.value)
    verify(find(missingText,"bio")<0 && find(nullText,"bio")>=0)
    var inscope missingAgain <- derive_from_json(missingText,type<PresenceUser>,"user",true)
    var inscope nullAgain <- derive_from_json(nullText,type<PresenceUser>,"user",true)
    var inscope presentAgain <- derive_from_json(derive_to_json(presentValue.value),type<PresenceUser>,"user",true)
    verify(missingAgain.ok && nullAgain.ok && presentAgain.ok)
    verify(derive_equal(missing.value,missingAgain.value) && derive_equal(nul.value,nullAgain.value) && derive_equal(presentValue.value,presentAgain.value))
    verify(!derive_equal(missing.value,nul.value) && derive_hash(missing.value)==derive_hash(missingAgain.value))
    verify(find(derive_debug(missing.value),"Missing")>=0 && find(derive_debug(nul.value),"Null")>=0)
    // Required nullable is different from optional: absent key is still an error.
    var inscope absentRequired <- derive_from_json("\{\"displayName\":\"A\"\}",type<PresenceUser>)
    verify(!absentRequired.ok && absentRequired.errors[0].code=="json_missing" && absentRequired.errors[0].path=="nickname")
    var inscope wrong <- derive_from_json("\{\"displayName\":\"A\",\"nickname\":3,\"bio\":4\}",type<PresenceUser>)
    verify(!wrong.ok && length(wrong.errors)==2 && wrong.errors[0].code=="json_type")
    // All present payloads are validated, while None/missing/null are skipped.
    var inscope invalid <- derive_from_json("\{\"displayName\":\"A\",\"nickname\":null,\"bio\":\"x\",\"rank\":0,\"level\":0,\"detail\":\{\"score\":-1,\"values\":[]\}\}",type<PresenceUser>,"user",true)
    verify(!invalid.ok && length(invalid.errors)==4 && invalid.errors[0].path=="user.bio" && invalid.errors[1].path=="user.detail.score")
    var inscope optionArray <- derive_from_json("[null,\{\"score\":2,\"values\":[1]\}]",type<array<$Option<PresenceDetail>>>,"items",true)
    verify(optionArray.ok && optionArray.value[0] is none && optionArray.value[1] is some)
    var inscope rootNull <- derive_from_json("null",type<$JsonField<int>>)
    var inscope rootValue <- derive_from_json("7",type<$Option<int>>)
    verify(rootNull.ok && rootNull.value is null_value && rootValue.ok && rootValue.value as some==7)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive JSON presence checks OK\n")
}
