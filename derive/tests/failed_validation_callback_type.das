options gen2
require ../lib/derive.das
[derive(validate=true)]
struct Invalid {
    @validate_each=1
    value:array<int>
}

[export]
def main() {
    var inscope value:Invalid
    var inscope errors <- derive_validate(value)
}
