options gen2
require ../lib/derive.das
[derive(json=true)]
struct Invalid {
@json_name="same"
first:int
@json_name="same"
second:int
}
[export]
def main() {}
