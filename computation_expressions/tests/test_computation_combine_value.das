options gen2
require ../lib/computation.das
[export]
def main() {
    let bad = computation(ResultBuilder()) {
        if (true) { return 1 } else { return 2 }
        return 3
    }
    print("{bad}\n")
}
