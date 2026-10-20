options gen2
require daslib/option
struct Owned {payload:$Option<array<int>>}
[export]
def main() {
    var inscope items <- [1,2]
    var inscope source:Owned
    source.payload <- move_some(items)
    var inscope result <- move_some(source)
    if(source.payload is some) {panic("SDK AOT move_some did not clear nested variant source")}
    verify(result is some && (result as some).payload is some)
    verify(length(((result as some).payload as some))==2)
    print("SDK move_some source cleared OK\n")
}
