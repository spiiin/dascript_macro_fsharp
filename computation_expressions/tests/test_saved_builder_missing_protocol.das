options gen2
require ../lib/computation_macro.das
struct UnknownBuilder {}
[export]
def main() {
    let builder=UnknownBuilder()
    let result=computation(builder) {return 1}
}
