options gen2
require ../lib/derive.das

[export]
def main() {
    var value:int?
    var inscope changes <- derive_diff(value,value)
}
