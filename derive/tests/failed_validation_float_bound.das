options gen2
require ../lib/derive.das
[derive(validate=true)]
struct Invalid {
@validate_max=9007199254740993l
value:double
}
[export]
def main() {}
