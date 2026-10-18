options gen2
module parser_builder public
require ./builder_protocol.das public
require daslib/strings_convert
require daslib/strings_boost

struct ParseDiagnostic {
    position:int
    line:int
    column:int
    expected:string
}
struct ParserBuilder {
    text:string
    position:int
}
struct ParserLiteral {text:string}
struct ParserInteger {_ce_marker:uint8}
struct ParserEnd {_ce_marker:uint8}
struct ParserSpaces {_ce_marker:uint8}
def parser_literal(text:string) {return ParserLiteral(text=text)}
def parser_int() {return ParserInteger()}
def parser_eof() {return ParserEnd()}
def parser_spaces() {return ParserSpaces()}
def parser_choice(left,right:auto) {return (parserAlternatives=true,left=left,right=right)}

def parser_ok(value:auto(T); position:int) {
    static_assert(typeinfo can_copy(type<T>),"ParserBuilder requires copyable parsed values")
    return variant<parsed:tuple<value:T -const -&;position:int>;failure:ParseDiagnostic>(parsed=(value=value,position=position))
}
def parser_error(builder:ParserBuilder; position:int; expected:string; unused:type<auto(T)>) {
    var line=1
    var column=1
    for(i in range(position)) {
        if(character_at(builder.text,i)==10) {line++;column=1} else {column++}
    }
    return variant<parsed:tuple<value:T -const -&;position:int>;failure:ParseDiagnostic>(failure=ParseDiagnostic(position=position,line=line,column=column,expected=expected))
}
def parser_read(builder:ParserBuilder; op:ParserLiteral) {
    var matched=0
    while(matched<length(op.text) && builder.position+matched<length(builder.text)
            && character_at(builder.text,builder.position+matched)==character_at(op.text,matched)) {matched++}
    if(matched!=length(op.text)) {return parser_error(builder,builder.position+matched,"'{op.text}'",type<string>)}
    return parser_ok(op.text,builder.position+matched)
}
def parser_read(builder:ParserBuilder; op:ParserInteger) {
    var end=builder.position
    if(end<length(builder.text) && character_at(builder.text,end)==45) {end++}
    let digits=end
    while(end<length(builder.text) && character_at(builder.text,end)>=48 && character_at(builder.text,end)<=57) {end++}
    if(end==digits) {return parser_error(builder,end,"integer",type<int>)}
    let number=try_to_int(slice(builder.text,builder.position,end))
    if(!is_ok(number)) {return parser_error(builder,builder.position,"32-bit integer",type<int>)}
    return parser_ok(unwrap(number),end)
}
def parser_read(builder:ParserBuilder; op:ParserSpaces) {
    var end=builder.position
    while(end<length(builder.text)) {
        let ch=character_at(builder.text,end)
        if(ch!=32 && ch!=9 && ch!=10 && ch!=13) {break}
        end++
    }
    return parser_ok(CeUnit(),end)
}
def parser_read(builder:ParserBuilder; op:ParserEnd) {
    if(builder.position!=length(builder.text)) {return parser_error(builder,builder.position,"end of input",type<CeUnit>)}
    return parser_ok(CeUnit(),builder.position)
}
// Both alternatives start at the same cursor; keep the furthest diagnostic.
def parser_read(builder:ParserBuilder; op:tuple<parserAlternatives:bool;left:auto(L);right:auto(R)>) {
    let left=parser_read(builder,op.left)
    if(left is parsed) {return left}
    let right=parser_read(builder,op.right)
    if(right is parsed) {return right}
    if((left as failure).position>(right as failure).position) {return left}
    if((left as failure).position==(right as failure).position) {
        var diagnostic=left as failure
        diagnostic.expected+=" or {(right as failure).expected}"
        return variant type<typedecl(left)>(failure=diagnostic)
    }
    return right
}
def ce_protocol(builder:ParserBuilder) {return CeValueProtocol()}
def ce_source(builder:ParserBuilder; source:ParserLiteral) {return parser_read(builder,source)}
def ce_source(builder:ParserBuilder; source:ParserInteger) {return parser_read(builder,source)}
def ce_source(builder:ParserBuilder; source:ParserEnd) {return parser_read(builder,source)}
def ce_source(builder:ParserBuilder; source:ParserSpaces) {return parser_read(builder,source)}
def ce_source(builder:ParserBuilder; source:tuple<parserAlternatives:bool;left:auto(L);right:auto(R)>) {return parser_read(builder,source)}
def ce_unwrap(builder:ParserBuilder; source:variant<parsed:tuple<value:auto(T);position:int>;failure:ParseDiagnostic>) : T {return (source as parsed).value}
def ce_return(builder:ParserBuilder; value:auto) {return parser_ok(value,builder.position)}
def ce_zero(builder:ParserBuilder) {return parser_ok(CeUnit(),builder.position)}
def ce_bind(var builder:ParserBuilder; source:variant<parsed:tuple<value:auto(T);position:int>;failure:ParseDiagnostic>;
            next:block<(value:T):auto(R)>) : R {
    if(source is failure) {return variant type<R>(failure=source as failure)}
    builder.position=(source as parsed).position
    return invoke(next,(source as parsed).value)
}
def ce_return_from(var builder:ParserBuilder; source:variant<parsed:tuple<value:auto(T);position:int>;failure:ParseDiagnostic>) {
    if(source is parsed) {builder.position=(source as parsed).position}
    return source
}
def ce_combine(var builder:ParserBuilder; first:variant<parsed:tuple<value:CeUnit;position:int>;failure:ParseDiagnostic>;
               next:block<():auto(R)>) : R {
    if(first is failure) {return variant type<R>(failure=first as failure)}
    builder.position=(first as parsed).position
    return invoke(next)
}
def ce_loop_failed(builder:ParserBuilder; step:variant<parsed:tuple<value:CeUnit;position:int>;failure:ParseDiagnostic>) {return step is failure}
def ce_loop_append(var builder:ParserBuilder; first,step:variant<parsed:tuple<value:CeUnit;position:int>;failure:ParseDiagnostic>) {
    if(first is failure) {return first}
    if(step is parsed) {builder.position=(step as parsed).position}
    return step
}

// Named subgrammar: a function pointer owns no stack captures.
def parser_call(callback:function<(cursor:ParserBuilder):auto(R)>) {
    return (parserFunction=true,callback=callback)
}
def parser_read(builder:ParserBuilder; op:tuple<parserFunction:bool;callback:function<(cursor:ParserBuilder):auto(R)>>) : R {
    return invoke(op.callback,builder)
}
def ce_source(builder:ParserBuilder; op:tuple<parserFunction:bool;callback:function<(cursor:ParserBuilder):auto(R)>>) : R {
    return parser_read(builder,op)
}
