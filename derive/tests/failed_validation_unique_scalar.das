options gen2
require ../lib/derive.das
[derive(validate=true)]
struct Invalid {
    @validate_unique_by="key"
    value:int
}
def key(value:int) : int {return value}
[export]
def main() {
    var inscope value:Invalid
    var inscope errors <- derive_validate(value)
}
