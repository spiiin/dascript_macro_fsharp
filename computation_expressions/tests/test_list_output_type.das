options gen2
require ../lib/computation.das
[export]
def main() {
    var inscope invalid <- computation(ListBuilder(type<string>)) { return 42 }
}
