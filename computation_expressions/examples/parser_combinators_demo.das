options gen2
require ../lib/computation_macro.das
require ../lib/parser_builder.das

def optional_tag(cursor:ParserBuilder) {
    return computation(cursor) {
        parser_literal("hp=") |> bind
        let health=parser_int() |> bind
        return health
    }
}
def numbers(text:string) {
    return <- computation(ParserBuilder(text=text)) {
        parser_literal("[") |> bind
        // Once '[' matched, report a malformed list instead of another grammar.
        parser_commit() |> bind
        var values & = parser_sep_by(parser_int(),parser_literal(",")) |> bind
        parser_literal("]") |> bind
        parser_eof() |> bind
        return <- values
    }
}
[export]
def main() {
    var inscope values <- numbers("[1,-2,3]")
    assert(values is parsed && length((values as parsed).value)==3)
    var inscope bad <- numbers("[1,]")
    assert(bad is failure && (bad as failure).committed)
    print("{(bad as failure).expected} at {(bad as failure).line}:{(bad as failure).column}\n")
    let optional=computation(ParserBuilder(text="other")) {
        return parser_optional(parser_attempt(parser_call(@@optional_tag))) |> return_from
    }
    assert((optional as parsed).value is none)
    let count=computation(ParserBuilder(text="aaa")) {
        var matches & = parser_many1(parser_literal("a")) |> bind
        parser_eof() |> bind
        return length(matches)
    }
    assert((count as parsed).value==3)
    print("Parser combinators demo OK\n")
}
