options gen2
require ../lib/derive.das

[export]
def main() {
    var inscope changes <- derive_diff(1,"one")
}
