options gen2
require ../lib/computation_macro.das
require ../lib/parser_builder.das
[export]
def main() {
    let value=computation(ParserBuilder(text="aa")) {
        let items=parser_many(parser_literal("a")) |> bind
        return length(items)
    }
}
