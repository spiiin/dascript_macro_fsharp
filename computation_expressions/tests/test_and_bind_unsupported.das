options gen2
require ../lib/computation_macro.das
require ../lib/reader_builder.das
[export]
def main() {
    let value = computation(ReaderBuilder(0)) { let p = reader_value(1) |> and_bind(reader_value(2)) |> bind; return p }
    print("{value}")
}
