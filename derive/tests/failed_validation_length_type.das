options gen2
require ../lib/derive.das
[derive(validate=true)]
struct Invalid {
@validate_non_empty
value:int
}
[export]
def main() {}
