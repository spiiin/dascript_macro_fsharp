options gen2
require ../lib/derive.das

[export]
def main() {
    let patch=derive_make_patch("old","new")
    var inscope result <- derive_apply_patch(1,patch)
}
