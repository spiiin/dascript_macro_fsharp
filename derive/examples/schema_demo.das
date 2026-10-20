options gen2
require ./schema_model.das
[derive(json=true,validate=true)]
struct SchemaNumbers {
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
variant SchemaLookalike {missing;null_value:string;present:int}
[export]
def main() {
    let before=schema_default_calls
    let strict=derive_json_schema(type<SchemaPlayer>)
    verify(schema_default_calls==before)
    print("STRICT {strict}\n")
    print("LOOSE {derive_json_schema(type<SchemaPlayer>,false)}\n")
    print("TREE {derive_json_schema(type<SchemaTree>)}\n")
    print("ACTION {derive_json_schema(type<SchemaAction>)}\n")
    print("ROLE {derive_json_schema(type<SchemaRole>)}\n")
    print("ARRAY {derive_json_schema(type<array<$Option<int>>>)}\n")
    print("FIXED {derive_json_schema(type<int[2]>)}\n")
    print("FIELD {derive_json_schema(type<$JsonField<int>>)}\n")
    print("PRESENCE {derive_json_schema(type<SchemaPresence>)}\n")
    print("INT8 {derive_json_schema(type<int8>)}\n")
    print("UINT64 {derive_json_schema(type<uint64>)}\n")
    print("MATRIX {derive_json_schema(type<int[2][3]>)}\n")
    print("NUMBERS {derive_json_schema(type<SchemaNumbers>)}\n")
    print("LOOKALIKE {derive_json_schema(type<SchemaLookalike>)}\n")
    print("Derive schema demo OK\n")
}
