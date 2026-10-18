options gen2
require ../recognizers.das
require daslib/match
[export]
def main() {
    let result=match ("oops") {
        (integer(_) => found(n)) => n
    }
    print("{result}")
}
