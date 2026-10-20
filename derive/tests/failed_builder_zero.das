options gen2
require ../lib/derive.das
[derive(builder=true,validate=true)]
struct Bad {}
[export]
def main() {var inscope b <- derive_builder(type<Bad>);var inscope r <- derive_build(b)}
