options gen2
require ../lib/computation.das
[export]
def main() {
    let bad = computation(ResultBuilder()) {
        for (i in range(3)) { return i }
    }
    print("{bad}\n")
}
