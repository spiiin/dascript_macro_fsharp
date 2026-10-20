options gen2
require ../lib/derive.das
[derive(validate=true)]
struct Invalid {
@validate_min_length=5
@validate_max_length=2
value:string
}
[export]
def main() {}
