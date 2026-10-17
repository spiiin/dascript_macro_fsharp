options gen2
require ../lib/computation.das
[export]
def main() {
    let bad = computation(ResultBuilder()) {
        try_finally($ { return 42 }, $ { return 1 })
    }
    print("{bad}\n")
}
