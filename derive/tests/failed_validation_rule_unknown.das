options gen2
require ../lib/derive.das
[derive(validate=true)]
struct Invalid {
@validate_typo=1
value:int
}
[export]
def main() {}
