options gen2
require ../lib/computation.das
[export]
def main() {
    let bad = computation(ResultBuilder()) { try_finally(1, 2) }
    print("{bad}\n")
}
