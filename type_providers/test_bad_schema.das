options gen2
require json_provider
[json_provider(schema="tests/bad_schema.json")]
struct Bad {}
[export]
def main() {}
