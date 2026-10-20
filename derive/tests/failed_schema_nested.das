options gen2
require ../lib/derive.das
struct Bad {x:int}
[derive]
struct Disabled {x:int}
[derive(json=true)]
struct Parent {child:Bad}
def derive_json_encode(value:Bad) : JsonValue? {return JV(value.x)}
def derive_json_read(node:JsonValue?;var value:Bad;path:string;var errors:array<ValidationIssue>;strict:bool) {}
[export]
def main() {let value=derive_json_schema(type<Parent>)}
