options gen2
options stack = 1048576
require ../lib/computation_macro.das
require ../lib/parser_builder.das
var rightCalls=0

def cut_branch(cursor:ParserBuilder) {
    return computation(cursor) {
        parser_literal("a") |> bind
        parser_commit() |> bind
        parser_literal("b") |> bind
        return 1
    }
}
def right_branch(cursor:ParserBuilder) {
    rightCalls++
    return computation(cursor) {parser_literal("ac") |> bind;return 2}
}
def earlier_cut(cursor:ParserBuilder) {
    return computation(cursor) {
        parser_commit() |> bind
        parser_attempt(parser_literal("ab")) |> bind
        return 1
    }
}
def prefixed_attempt(cursor:ParserBuilder) {
    return computation(cursor) {
        parser_literal("a") |> bind
        parser_attempt(parser_literal("b")) |> bind
        return 1
    }
}
def fallback_array(cursor:ParserBuilder) {
    rightCalls++
    var values:array<string>
    return <- parser_ok_move(values,cursor.position)
}
def int_list(text:string) {
    return <- computation(ParserBuilder(text=text)) {
        var items & = parser_sep_by(parser_int(),parser_literal(",")) |> bind
        parser_eof() |> bind
        return <- items
    }
}
def group(cursor:ParserBuilder) {
    return <- computation(cursor) {
        parser_literal("[") |> bind
        var items & = parser_sep_by(parser_int(),parser_literal(",")) |> bind
        parser_literal("]") |> bind
        return <- items
    }
}
[export]
def main() {
    let absent=computation(ParserBuilder(text="x")) {
        let value=parser_optional(parser_int()) |> bind
        parser_literal("x") |> bind
        return value
    }
    assert(absent is parsed && (absent as parsed).value is none && (absent as parsed).position==1)
    let present=computation(ParserBuilder(text="-42")) {
        let value=parser_optional(parser_int()) |> bind
        return value
    }
    assert(((present as parsed).value as some) == -42)
    let partial=computation(ParserBuilder(text="ax")) {
        return parser_optional(parser_literal("ab")) |> return_from
    }
    assert(partial is failure && (partial as failure).position==1)
    let rewind=computation(ParserBuilder(text="ax")) {
        return parser_optional(parser_attempt(parser_literal("ab"))) |> return_from
    }
    assert(rewind is parsed && (rewind as parsed).position==0 && (rewind as parsed).value is none)
    let prefixFailure=computation(ParserBuilder(text="ax")) {
        return parser_optional(parser_call(@@prefixed_attempt)) |> return_from
    }
    assert(prefixFailure is failure && (prefixFailure as failure).rewind_position==1)
    let overflow=computation(ParserBuilder(text="2147483648")) {
        return parser_optional(parser_int()) |> return_from
    }
    assert(overflow is failure && (overflow as failure).consumed)
    let count=computation(ParserBuilder(text="aaa")) {
        var items & = parser_many(parser_literal("a")) |> bind
        parser_eof() |> bind
        return length(items)
    }
    assert((count as parsed).value==3 && (count as parsed).position==3)
    let zero=computation(ParserBuilder(text="")) {
        var items & = parser_many(parser_int()) |> bind
        return length(items)
    }
    assert((zero as parsed).value==0)
    var inscope one <- computation(ParserBuilder(text="aaa")) {return parser_many1(parser_literal("a")) |> return_from}
    assert(length((one as parsed).value)==3)
    var inscope missing <- computation(ParserBuilder(text="")) {return parser_many1(parser_int()) |> return_from}
    assert(missing is failure && (missing as failure).expected=="integer")
    var inscope incomplete <- computation(ParserBuilder(text="abax")) {return parser_many(parser_literal("ab")) |> return_from}
    assert(incomplete is failure && (incomplete as failure).position==3)
    var inscope stopped <- computation(ParserBuilder(text="abax")) {return parser_many(parser_attempt(parser_literal("ab"))) |> return_from}
    assert(stopped is parsed && (stopped as parsed).position==2 && length((stopped as parsed).value)==1)
    var inscope list <- int_list("1,-2,3")
    assert(length((list as parsed).value)==3 && (list as parsed).value[1] == -2)
    var inscope emptyList <- int_list("")
    assert(emptyList is parsed && length((emptyList as parsed).value)==0)
    var inscope trailing <- int_list("1,")
    assert(trailing is failure && (trailing as failure).position==2 && (trailing as failure).expected=="integer")
    var inscope noSeparator <- computation(ParserBuilder(text="aaa")) {
        return parser_sep_by(parser_literal("a"),parser_literal("")) |> return_from
    }
    assert(noSeparator is parsed && length((noSeparator as parsed).value)==3 && (noSeparator as parsed).position==3)
    rightCalls=0
    let committed=computation(ParserBuilder(text="ac")) {
        return parser_choice(parser_call(@@cut_branch),parser_call(@@right_branch)) |> return_from
    }
    assert(committed is failure && (committed as failure).committed && rightCalls==0)
    let attempted=computation(ParserBuilder(text="ac")) {
        return parser_choice(parser_attempt(parser_call(@@cut_branch)),parser_call(@@right_branch)) |> return_from
    }
    assert((attempted as parsed).value==2 && rightCalls==1)
    let outerCut=computation(ParserBuilder(text="ac")) {
        return parser_choice(parser_call(@@earlier_cut),parser_call(@@right_branch)) |> return_from
    }
    assert(outerCut is failure && (outerCut as failure).committed && rightCalls==1)
    let localChoice=computation(ParserBuilder(text="b")) {
        parser_commit() |> bind
        return parser_choice(parser_literal("a"),parser_literal("b")) |> return_from
    }
    assert((localChoice as parsed).value=="b" && (localChoice as parsed).committed)
    let wrappedCut=computation(ParserBuilder(text="ax")) {
        return parser_choice(parser_commit(parser_literal("ab")),parser_literal("ax")) |> return_from
    }
    assert(wrappedCut is failure && (wrappedCut as failure).committed)
    let diagnostic=computation(ParserBuilder(text="\nax")) {
        parser_spaces() |> bind
        return parser_attempt(parser_commit(parser_literal("ab"))) |> return_from
    }
    assert(diagnostic is failure && !(diagnostic as failure).committed && (diagnostic as failure).rewound)
    assert((diagnostic as failure).position==2 && (diagnostic as failure).line==2 && (diagnostic as failure).column==2)
    assert((diagnostic as failure).expected=="'ab'")
    var inscope fatal <- computation(ParserBuilder(text="")) {
        return parser_choice(parser_attempt(parser_many(parser_literal(""))),parser_call(@@fallback_array)) |> return_from
    }
    assert(fatal is failure && (fatal as failure).fatal && rightCalls==1)
    var inscope nullable <- computation(ParserBuilder(text="")) {return parser_many1(parser_optional(parser_int())) |> return_from}
    assert(nullable is failure && (nullable as failure).fatal)
    var inscope spaces <- computation(ParserBuilder(text="  ")) {return parser_many(parser_spaces()) |> return_from}
    assert(spaces is failure && (spaces as failure).fatal && (spaces as failure).position==2)
    var inscope emptyItem <- computation(ParserBuilder(text="")) {return parser_sep_by(parser_literal(""),parser_literal(",")) |> return_from}
    assert(emptyItem is failure && (emptyItem as failure).fatal)
    var inscope groups <- computation(ParserBuilder(text="[1,2][3]")) {
        var values & = parser_many(parser_call(@@group)) |> bind
        parser_eof() |> bind
        return <- values
    }
    assert(length((groups as parsed).value)==2 && (groups as parsed).value[0][1]==2 && (groups as parsed).value[1][0]==3)
    let optionalGroup=computation(ParserBuilder(text="[7]")) {
        var value & = parser_optional(parser_call(@@group)) |> bind
        return (value as some)[0]
    }
    assert((optionalGroup as parsed).value==7)
    print("Parser combinator checks OK\n")
}
