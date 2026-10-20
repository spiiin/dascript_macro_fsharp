options gen2
require ../lib/derive.das
[derive(validate=true)]
struct Invalid {
@validate_min="bad"
value:int
}
[export]
def main() {}
