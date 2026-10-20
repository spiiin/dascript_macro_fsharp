options gen2
require ../lib/derive.das
struct Bad {x:int}
[derive]
struct Disabled {x:int}
[export]
def main() {let value=derive_json_schema(type<table<string;int>>)}
