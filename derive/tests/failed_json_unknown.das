options gen2
require ../lib/derive.das
[derive(json=true)]
struct Invalid {
@json_typo
value:int
}
[export]
def main() {}
