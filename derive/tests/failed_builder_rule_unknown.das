options gen2
require ../lib/derive.das
[derive(builder=true,validate=true)]
struct Bad {@builder_typo x:int}
