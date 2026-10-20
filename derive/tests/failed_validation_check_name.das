options gen2
require ../lib/derive.das
[derive(validate=true,check="bad.name")]
struct Invalid {

value:int
}
[export]
def main() {}
