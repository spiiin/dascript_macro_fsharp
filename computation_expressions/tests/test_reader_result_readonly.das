options gen2
require ../lib/computation_macro.das
require ../lib/reader_result_builder.das
struct Rules {limit:int=2}
[export]
def main() {
    let value=computation(ReaderResultBuilder(Rules())) {
        let config=reader_ask() |> bind
        config.limit=99
        return config.limit
    }
}
