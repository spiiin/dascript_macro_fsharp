options gen2
require ../lib/computation.das
[export]
def main() {
    let invalid = computation(WriterBuilder()) {
        for (i in range(3)) { return i }
    }
    print("{invalid}\n")
}
