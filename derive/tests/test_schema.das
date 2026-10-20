options gen2
require ../examples/schema_model.das
require daslib/rtti
require strings
require daslib/templates

[derive(json=true,validate=true)]
struct SchemaNumberChecks {
    @json_default=2ul
    @validate_min=1ul
    x:uint64=3ul
    @json_required=false
    y:uint=4294967295u
    @json_required=false
    @validate_min=-9223372036854775807l
    signed:int64=-7l
    @json_required=false
    @validate_min=0.1
    @validate_max=2.5
    f:float=1.5
    @json_required=false
    g:double=-2.5lf
}

variant SchemaFieldLookalike {missing;null_value:string;present:int}

typedef SchemaAlias=SchemaPlayer
[template(t)]
def generic_schema(t:auto(T)) : string {return derive_json_schema(type<T>)}

def check() {
    let calls=schema_default_calls
    let strict=derive_json_schema(type<SchemaPlayer>)
    verify(strict==derive_json_schema(type<SchemaAlias>) && strict==generic_schema(type<SchemaPlayer>))
    let loose=derive_json_schema(type<SchemaPlayer>,false)
    verify(calls==schema_default_calls && strict==derive_json_schema(type<SchemaPlayer>,true))
    verify(find(strict,"2020-12/schema")>=0 && find(strict,"byteMinLength")>=0)
    var node:JsonValue?
    var message:string
    try {
        node=read_json(strict,message)
        verify(node!=null && message=="")
        let defs=node?["$defs"]
        let player=defs?["schema_model::SchemaPlayer"]
        verify(!(player?["additionalProperties"] as _bool))
        let required=player?["required"]
        verify(length(required as _array)==4 && (required?[0] as _string)=="displayName")
        verify(!key_exists(player?["properties"],"session"))
        verify(player?["properties"]?["code"]?["default"] as _string=="ok")
        verify(player?["properties"]?["defaults"]?["x-das-native-default"] as _bool)
        verify(player?["x-das-check"] as _string=="schema_check_player")
    } recover {let error="{this_context().last_exception}";delete_json(node);panic(error)}
    delete_json(node)
    node=read_json(loose,message)
    verify(node?["$defs"]?["schema_model::SchemaPlayer"]?["additionalProperties"] as _bool)
    delete_json(node)
    var inscope reserved <- derive_from_json("\{\"displayName\":\"forbidden\",\"role\":\"Mage\",\"stats\":\{\"health\":100\},\"inventory\":[\{\"id\":1,\"count\":1\}]\}",type<SchemaPlayer>,"player",true)
    verify(!reserved.ok && reserved.errors[0].code=="reserved")
    var inscope duplicate <- derive_from_json("\{\"displayName\":\"Alice\",\"role\":\"Mage\",\"stats\":\{\"health\":100\},\"inventory\":[\{\"id\":1,\"count\":1\},\{\"id\":1,\"count\":2\}]\}",type<SchemaPlayer>,"player",true)
    verify(!duplicate.ok && length(duplicate.errors)==1)
    var inscope unicode <- derive_from_json("\{\"displayName\":\"Alice\",\"role\":\"Mage\",\"stats\":\{\"health\":100\},\"inventory\":[\{\"id\":1,\"count\":1\}],\"code\":\"é\"\}",type<SchemaPlayer>,"player",true)
    verify(unicode.ok)
    node=read_json(derive_json_schema(type<SchemaNumberChecks>),message)
    verify(node!=null && message=="")
    let numbers=node?["$defs"]?["::SchemaNumberChecks"]?["properties"]
    verify(numbers?["x"]?["default"] as _longint==2l)
    verify(numbers?["y"]?["default"] as _longint==4294967295l)
    verify(numbers?["signed"]?["default"] as _longint== -7l)
    verify(numbers?["f"]?["default"] as _number==1.5lf)
    verify(numbers?["g"]?["default"] as _number== -2.5lf)
    delete_json(node)
    let lookalike=derive_json_schema(type<SchemaFieldLookalike>)
    verify(find(lookalike,"oneOf")>=0 && find(lookalike,"anyOf")== -1)
    let encoded=derive_to_json(SchemaFieldLookalike(null_value="text"))
    var inscope decoded <- derive_from_json(encoded,type<SchemaFieldLookalike>,"",true)
    verify(decoded.ok && decoded.value is null_value && decoded.value as null_value=="text")
    var inscope floatLoaded <- derive_from_json("\{\"f\":0.1\}",type<SchemaNumberChecks>,"",true)
    verify(floatLoaded.ok)
    let recursive=derive_json_schema(type<SchemaTree>)
    verify(find(recursive,"#/$defs/schema_model::SchemaTree")>=0)
    let fixed=derive_json_schema(type<int[2][3]>)
    verify(find(fixed,"minItems")>=0 && find(fixed,"maxItems")>=0)
    let role=derive_json_schema(type<SchemaRole>)
    verify(find(role,"Wizard")>=0)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive schema checks OK\n")
}
