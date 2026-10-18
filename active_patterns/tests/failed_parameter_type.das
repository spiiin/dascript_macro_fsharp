options gen2
require ../recognizers.das
require daslib/match
[export]
def main() {
    let result=match (12) {
        (at_least(_,"ten") => found(n)) => n
        _ => -1
    }
    print("{result}")
}
