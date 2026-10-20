options gen2
require ../lib/derive.das
[derive(validate=true)]
struct Invalid {
    @validate_each="check_value"
    value:array<int>
}
def check_value(value:int;path:string;var errors:array<ValidationIssue>) : bool {return true}
[export]
def main() {
    var inscope value:Invalid
    var inscope errors <- derive_validate(value)
}
