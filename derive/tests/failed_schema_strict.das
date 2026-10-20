options gen2
require ../lib/derive.das
struct Bad {x:int}
[derive]
struct Disabled {x:int}
[export]
def main() {var strict=true;let value=derive_json_schema(type<int>,strict)}
