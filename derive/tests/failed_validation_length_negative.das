options gen2
require ../lib/derive.das
[derive(validate=true)]
struct Invalid {
@validate_min_length=-1
value:string
}
[export]
def main() {}
