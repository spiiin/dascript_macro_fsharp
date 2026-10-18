options gen2
require ../lib/computation_macro.das
require ../lib/parser_builder.das
def assignment(text:string) {
    return computation(ParserBuilder(text=text)) {
        parser_literal("hp") |> bind
        parser_spaces() |> bind
        parser_literal("=") |> bind
        parser_spaces() |> bind
        let health=parser_int() |> bind
        parser_eof() |> bind
        return health
    }
}
[export]
def main() {
    let good=assignment("hp = 85")
    assert(good is parsed && (good as parsed).value==85 && (good as parsed).position==7)
    let bad=assignment("hp = nope")
    assert(bad is failure)
    print("expected {(bad as failure).expected} at {(bad as failure).line}:{(bad as failure).column}\n")
    print("Parser demo OK\n")
}
