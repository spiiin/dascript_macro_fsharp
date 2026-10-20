options gen2
require ../lib/derive.das
[derive(clone=true,validate=true)]
struct Invalid {value:int}
[export]
def main() {
    var value:Invalid
    let patch=derive_make_patch(value,value)
    var inscope result <- derive_apply_patch(value,patch)
}
