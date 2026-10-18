options gen2
require ../lib/computation_macro.das
require ../lib/parser_builder.das
require daslib/rtti
var effects=0
def number(text:string) {
    return computation(ParserBuilder(text=text)) {
        parser_spaces() |> bind
        let n=parser_int() |> bind
        parser_eof() |> bind
        return n
    }
}
def bracketed(cursor:ParserBuilder) {
    return computation(cursor) {
        parser_literal("[") |> bind
        let n=parser_int() |> bind
        parser_literal("]") |> bind
        return n
    }
}
def tagged(cursor:ParserBuilder) {
    return computation(cursor) {
        parser_literal("[id=") |> bind
        let n=parser_int() |> bind
        parser_literal("]") |> bind
        return n
    }
}
[export]
def main() {
    let good=number(" \n-42")
    assert(good is parsed && (good as parsed).value == -42 && (good as parsed).position==5)
    let bad=number(" \nx")
    assert(bad is failure && (bad as failure).position==2 && (bad as failure).line==2 && (bad as failure).column==1)
    assert(number("2147483648") is failure)
    assert(number("") is failure && number("-") is failure && number("12x") is failure)
    let choice=computation(ParserBuilder(text="abd")) {
        let word=parser_choice(parser_literal("abc"),parser_literal("abd")) |> bind
        parser_eof() |> bind
        return word
    }
    assert(choice is parsed && (choice as parsed).value=="abd")
    let farthest=computation(ParserBuilder(text="abx")) {
        return parser_choice(parser_literal("abcd"),parser_literal("z")) |> return_from
    }
    assert(farthest is failure && (farthest as failure).position==2)
    let tied=computation(ParserBuilder(text="x")) {
        return parser_choice(parser_literal("a"),parser_literal("b")) |> return_from
    }
    assert(tied is failure && (tied as failure).expected=="'a' or 'b'")
    let stopped=computation(ParserBuilder(text="x")) {
        parser_literal("a") |> bind
        effects++
        return 1
    }
    assert(stopped is failure && effects==0)
    let loop=computation(ParserBuilder(text="aaa")) {
        for(i in range(3)) {parser_literal("a") |> bind}
        parser_eof() |> bind
        return 3
    }
    assert(loop is parsed && (loop as parsed).position==3)
    let stoppedLoop=computation(ParserBuilder(text="ax")) {
        for(i in range(3)) {parser_literal("a") |> bind;effects++}
        return 3
    }
    assert(stoppedLoop is failure && effects==1)
    let nested=computation(ParserBuilder(text="[id=7]")) {
        let n=parser_choice(parser_call(@@bracketed),parser_call(@@tagged)) |> bind
        parser_eof() |> bind
        return n*2
    }
    assert(nested is parsed && (nested as parsed).value==14 && (nested as parsed).position==6)
    let scoped=ParserBuilder(text="42!")
    let first=computation(scoped) {let n=parser_int() |> bind; return n}
    assert(scoped.position==0 && (first as parsed).position==2)
    var closed=0
    var handled=0
    let failure=computation(ParserBuilder(text="bad")) {
        try_with($ {
            try_finally($ {
                let n=parser_int() |> bind
                return n
            }, $ {closed++})
        }, $(message:string) {handled++;return 0})
    }
    assert(failure is failure && closed==1 && handled==0)
    let recovered=computation(ParserBuilder(text="a42")) {
        try_with($ {
            parser_literal("a") |> bind
            panic("parser native panic")
            return 0
        }, $(message:string) {
            let n=parser_int() |> bind
            return n
        })
    }
    assert(recovered is parsed && (recovered as parsed).value==42 && (recovered as parsed).position==3)
    print("Parser checks OK\n")
}
