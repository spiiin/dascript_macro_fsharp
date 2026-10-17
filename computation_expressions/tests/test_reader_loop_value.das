options gen2
require ../lib/computation_macro.das
require ../lib/reader_builder.das
[export]
def main() {
    let value = computation(ReaderBuilder(1)) {
        for (i in range(3)) { return 42 }
        return 0
    }
    print("{value}")
}
