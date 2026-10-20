options gen2
require ../lib/derive.das
[derive(validate=true)]
struct Invalid {
    @validate_check="bad.name"
    value:int
}

[export]
def main() {
    var inscope value:Invalid
    var inscope errors <- derive_validate(value)
}
