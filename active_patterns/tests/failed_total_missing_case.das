options gen2
require ../recognizers.das
require daslib/match
[export]
def main() {
    let result=match (parity(3)) {
        Parity.even => "even"
    }
    print(result)
}
