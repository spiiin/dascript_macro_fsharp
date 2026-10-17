options gen2
require ../lib/computation.das
[export]
def main() {
    let bad = computation(ResultBuilder()) {
        return 1
        print("unreachable\n")
    }
    print("{bad}\n")
}
