options gen2
require ../recognizers.das
require daslib/match
[export]
def main() {
    let result=match (3) {
        (parity(_) => Parity.even) => "even"
        (parity(_) => Parity.odd) => "odd"
    }
    print(result)
}
