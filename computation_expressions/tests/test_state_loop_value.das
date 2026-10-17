options gen2
require ../lib/computation.das
[export]
def main() {
    let invalid = computation(StateBuilder(0)) {
        for (i in range(3)) { return i }
    }
    print("{invalid}\n")
}
