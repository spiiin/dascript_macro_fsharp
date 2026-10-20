options gen2
require ../lib/derive.das
[derive(clone=true,validate=true)]
struct Child {value:int}
[derive(clone=true,validate=true,patch=true)]
struct Invalid {value:Child}
[export]
def main() {
    var value:Invalid
    let patch=derive_make_patch(value,value)
    var inscope result <- derive_apply_patch(value,patch)
}
