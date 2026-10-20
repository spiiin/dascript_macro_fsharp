options gen2
require ../lib/derive.das
[derive(debug=false,equality=false,hash=false,validate=true,check="check_bad")]
struct Invalid {value:int}
def check_bad(value:Invalid;path:string;var errors:array<ValidationIssue>) : bool {return true}
[export]
def main() {}
