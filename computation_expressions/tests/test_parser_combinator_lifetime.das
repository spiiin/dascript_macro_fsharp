options gen2
options stack = 1048576
require ../lib/computation_macro.das
require ../lib/parser_builder.das
require ../lib/deferred_computation.das
require daslib/rtti
var calls=0
var closed=0
struct Resource {id:int}
def ce_dispose(var resource:Resource) {closed++}
def group(cursor:ParserBuilder) {
    return <- computation(cursor) {
        parser_literal("[") |> bind
        var items & = parser_sep_by(parser_int(),parser_literal(",")) |> bind
        parser_literal("]") |> bind
        return <- items
    }
}
def empty_group(cursor:ParserBuilder) {
    var values:array<int>
    return <- parser_ok_move(values,cursor.position)
}
def throwing_item(cursor:ParserBuilder) {
    return computation(cursor) {
        parser_literal("a") |> bind
        calls++
        if(calls==3) {panic("item failed")}
        return calls
    }
}
def check() {
    var inscope nested <- computation(ParserBuilder(text="[1,2][3]")) {
        var values & = parser_many(parser_call(@@group)) |> bind
        return <- values
    }
    assert(length((nested as parsed).value)==2 && (nested as parsed).value[0][0]==1)
    var inscope rollback <- computation(ParserBuilder(text="[1,2x")) {
        return parser_choice(parser_attempt(parser_call(@@group)),parser_call(@@empty_group)) |> return_from
    }
    assert(rollback is parsed && length((rollback as parsed).value)==0 && (rollback as parsed).position==0)
    var inscope partial <- computation(ParserBuilder(text="abax")) {return parser_many(parser_literal("ab")) |> return_from}
    assert(partial is failure)
    var inscope trailing <- computation(ParserBuilder(text="1,2,")) {return parser_sep_by(parser_int(),parser_literal(",")) |> return_from}
    assert(trailing is failure)
    var inscope optional <- computation(ParserBuilder(text="[1,2]")) {return parser_optional(parser_call(@@group)) |> return_from}
    assert(length((optional as parsed).value as some)==2)
    var inscope absent <- computation(ParserBuilder(text="x")) {return parser_optional(parser_call(@@group)) |> return_from}
    assert((absent as parsed).value is none)
    calls=0
    let before=closed
    var caught=false
    try {
        var inscope panicked <- computation(ParserBuilder(text="aaaa")) {
            let resource=Resource(id=1) |> use_resource
            return parser_many(parser_call(@@throwing_item)) |> return_from
        }
    } recover {caught=true}
    assert(caught && closed==before+1 && calls==3)
    var inscope recovered <- computation(ParserBuilder(text="[1,2]")) {
        try_with($ {
            var values & = parser_call(@@group) |> bind
            panic("after owned bind")
            return <- values
        }, $(message:string) {
            var fallback:array<int>
            fallback |> push(99)
            return <- fallback
        })
    }
    assert(length((recovered as parsed).value)==1 && (recovered as parsed).value[0]==99)
    caught=false
    try {
        var inscope cleanupError <- computation(ParserBuilder(text="[1,2]")) {
            try_finally($ {
                var values & = parser_call(@@group) |> bind
                return <- values
            }, $ {panic("cleanup")})
        }
    } recover {caught=true}
    assert(caught)
    var inscope saved <- deferred(ParserBuilder(text="1,2")) {
        var items & = parser_sep_by(parser_int(),parser_literal(",")) |> bind
        return <- items
    }
    var inscope first <- run_deferred(saved)
    var inscope second <- run_deferred(saved)
    (first as parsed).value[0]=7
    assert((second as parsed).value[0]==1)
    delete saved
    assert((first as parsed).value[1]==2)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Parser combinator lifetime checks OK\n")
}
