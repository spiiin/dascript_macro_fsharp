options gen2
require ../lib/derive.das
[derive(clone=true,validate=true,patch=true)]
struct EmptyPatchRoot {}
[export]
def main() {
    let patch=derive_make_patch(EmptyPatchRoot(),EmptyPatchRoot())
}
