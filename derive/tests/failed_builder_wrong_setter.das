options gen2
require ../lib/derive.das
[derive(builder=true,validate=true)]
struct Bad {x:int}
[export]
def main() {var inscope b <- derive_builder(type<Bad>);b |> builder_x("bad")}
