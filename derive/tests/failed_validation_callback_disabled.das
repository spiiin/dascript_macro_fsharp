options gen2
require ../lib/derive.das
[derive]
struct Invalid {
    @validate_check="check_value"
    value:int
}

[export]
def main() {
    var inscope value:Invalid
    var inscope errors <- derive_validate(value)
}
