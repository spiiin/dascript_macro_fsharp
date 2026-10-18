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
    committed:bool
    rewound:bool
    rewind_position:int
    consumed:bool
    fatal:bool
}
struct ParserBuilder {
    text:string
    position:int
    committed:bool
}
struct ParserLiteral {text:string}
struct ParserInteger {_ce_marker:uint8}
struct ParserEnd {_ce_marker:uint8}
struct ParserSpaces {_ce_marker:uint8}
struct parserAlternativesTag {_ce_marker:uint8}
struct parserCutTag {_ce_marker:uint8}
struct parserAttemptTag {_ce_marker:uint8}
struct parserOptionalTag {_ce_marker:uint8}
struct parserRepeatTag {_ce_marker:uint8}
struct parserSeparatedTag {_ce_marker:uint8}

def parser_literal(text:string) {return ParserLiteral(text=text)}
def parser_int() {return ParserInteger()}
def parser_eof() {return ParserEnd()}
def parser_spaces() {return ParserSpaces()}
def parser_choice(left,right:auto) {return (parserAlternatives=parserAlternativesTag(),left=left,right=right)}

def parser_ok(value:auto(T); position:int; committed:bool=false) {
    static_assert(typeinfo can_copy(type<T>),"ParserBuilder requires copyable parsed values")
    return variant<parsed:tuple<value:T -const -&;position:int;committed:bool>;failure:ParseDiagnostic>(parsed=(value=value,position=position,committed=committed))
}
def parser_error(builder:ParserBuilder; position:int; expected:string; unused:type<auto(T)>) {
    var line=1
    var column=1
    for(i in range(position)) {
        if(character_at(builder.text,i)==10) {line++;column=1} else {column++}
    }
    return variant<parsed:tuple<value:T -const -&;position:int;committed:bool>;failure:ParseDiagnostic>(failure=ParseDiagnostic(position=position,line=line,column=column,expected=expected,committed=builder.committed,consumed=position>builder.position))
}
def parser_read(builder:ParserBuilder; op:ParserLiteral) {
    var matched=0
    while(matched<length(op.text) && builder.position+matched<length(builder.text)
            && character_at(builder.text,builder.position+matched)==character_at(op.text,matched)) {matched++}
    if(matched!=length(op.text)) {return parser_error(builder,builder.position+matched,"'{op.text}'",type<string>)}
    return parser_ok(op.text,builder.position+matched,builder.committed)
}
def parser_read(builder:ParserBuilder; op:ParserInteger) {
    var end=builder.position
    if(end<length(builder.text) && character_at(builder.text,end)==45) {end++}
    let digits=end
    while(end<length(builder.text) && character_at(builder.text,end)>=48 && character_at(builder.text,end)<=57) {end++}
    if(end==digits) {return parser_error(builder,end,"integer",type<int>)}
    let number=try_to_int(slice(builder.text,builder.position,end))
    if(!is_ok(number)) {
        var result=parser_error(builder,builder.position,"32-bit integer",type<int>)
        (result as failure).consumed=true
        return result
    }
    return parser_ok(unwrap(number),end,builder.committed)
}
def parser_read(builder:ParserBuilder; op:ParserSpaces) {
    var end=builder.position
    while(end<length(builder.text)) {
        let ch=character_at(builder.text,end)
        if(ch!=32 && ch!=9 && ch!=10 && ch!=13) {break}
        end++
    }
    return parser_ok(CeUnit(),end,builder.committed)
}
def parser_read(builder:ParserBuilder; op:ParserEnd) {
    if(builder.position!=length(builder.text)) {return parser_error(builder,builder.position,"end of input",type<CeUnit>)}
    return parser_ok(CeUnit(),builder.position,builder.committed)
}
// Ordered choice preserves the original always-backtracking contract unless cut.
def parser_read(builder:ParserBuilder; op:tuple<parserAlternatives:parserAlternativesTag;left:auto(L);right:auto(R)>) {
    var cursor=builder
    cursor.committed=false
    var inscope left <- parser_read(cursor,op.left)
    if(left is parsed) {
        (left as parsed).committed = (left as parsed).committed || builder.committed
        return <- left
    }
    if((left as failure).committed || (left as failure).fatal) {return <- left}
    var inscope right <- parser_read(cursor,op.right)
    if(right is parsed) {
        (right as parsed).committed = (right as parsed).committed || builder.committed
        return <- right
    }
    if((right as failure).committed || (right as failure).fatal) {return <- right}
    if((left as failure).position>(right as failure).position) {
        (left as failure).committed = (left as failure).committed || builder.committed
        return <- left
    }
    if((left as failure).position==(right as failure).position) {
        (left as failure).expected+=" or {(right as failure).expected}"
        (left as failure).committed = (left as failure).committed || builder.committed
        (left as failure).rewound = (left as failure).rewound && (right as failure).rewound
        return <- left
    }
    (right as failure).committed = (right as failure).committed || builder.committed
    return <- right
}

def parser_ok_move(var value:auto(T); position:int; committed:bool=false) {
    var inscope result:variant<parsed:tuple<value:T -const -&;position:int;committed:bool>;failure:ParseDiagnostic>
    // Separate assignment avoids shallow copies in SDK AOT variant initializers.
    (result as parsed).value <- value
    (result as parsed).position=position
    (result as parsed).committed=committed
    return <- result
}
def parser_failure(diagnostic:ParseDiagnostic; unused:type<auto(T)>) {
    return <- variant<parsed:tuple<value:T -const -&;position:int;committed:bool>;failure:ParseDiagnostic>(failure=diagnostic)
}
def private parser_rethrow(var owner:auto) {ce_owned_source_rethrow(owner)}

// Owning outcomes allow repetitions to return arrays without hidden cloning.
def ce_protocol(builder:ParserBuilder) {return CeOwnedProtocol()}
def ce_unwrap(builder:ParserBuilder; var source:variant<parsed:tuple<value:auto(T);position:int;committed:bool>;failure:ParseDiagnostic>) : T& {
    unsafe {return (source as parsed).value}
}
def ce_return(builder:ParserBuilder; value:auto) {return parser_ok(value,builder.position,builder.committed)}
def ce_return_move(builder:ParserBuilder; var value:auto) {return <- parser_ok_move(value,builder.position,builder.committed)}
def ce_zero(builder:ParserBuilder) {return parser_ok(CeUnit(),builder.position,builder.committed)}
def ce_delay(builder:ParserBuilder; body:block<():auto(R)>) : R {return <- invoke(body)}
def ce_bind(var builder:ParserBuilder; var source:variant<parsed:tuple<value:auto(T);position:int;committed:bool>;failure:ParseDiagnostic>;
            next:block<(var value:auto(V)):auto(R)>) : R {
    var inscope owner <- source
    if(owner is failure) {
        var diagnostic=owner as failure
        diagnostic.committed = diagnostic.committed || builder.committed
        return <- variant type<R>(failure=diagnostic)
    }
    builder.position=(owner as parsed).position
    builder.committed = builder.committed || (owner as parsed).committed
    var inscope result:R
    try {result <- invoke(next,(owner as parsed).value)} recover {parser_rethrow(owner)}
    return <- result
}
def ce_return_from(var builder:ParserBuilder; var source:variant<parsed:tuple<value:auto(T);position:int;committed:bool>;failure:ParseDiagnostic>) {
    if(source is parsed) {
        builder.position=(source as parsed).position
        (source as parsed).committed = (source as parsed).committed || builder.committed
        builder.committed=(source as parsed).committed
    } else {(source as failure).committed = (source as failure).committed || builder.committed}
    return <- source
}
def ce_combine(var builder:ParserBuilder; first:variant<parsed:tuple<value:CeUnit;position:int;committed:bool>;failure:ParseDiagnostic>;
               next:block<():auto(R)>) : R {
    if(first is failure) {return <- variant type<R>(failure=first as failure)}
    builder.position=(first as parsed).position
    builder.committed = builder.committed || (first as parsed).committed
    return <- invoke(next)
}
def ce_loop_failed(builder:ParserBuilder; step:variant<parsed:tuple<value:CeUnit;position:int;committed:bool>;failure:ParseDiagnostic>) {return step is failure}
def ce_collect_append(var builder:ParserBuilder; var first:variant<parsed:tuple<value:CeUnit;position:int;committed:bool>;failure:ParseDiagnostic>;
                      step:variant<parsed:tuple<value:CeUnit;position:int;committed:bool>;failure:ParseDiagnostic>) {
    if(first is failure) {return}
    first=step
    if(step is parsed) {
        builder.position=(step as parsed).position
        builder.committed = builder.committed || (step as parsed).committed
    }
}
def ce_collect_rethrow(builder:ParserBuilder; var result:auto) {parser_rethrow(result)}
def ce_try_with(builder:ParserBuilder; body:block<():auto(R)>; handler:block<(message:string):R>) : R {
    var inscope result:R
    var failed=false
    var message=""
    try {result <- invoke(body)} recover {message=ce_exception_message();failed=true}
    if(failed) {return <- invoke(handler,message)}
    return <- result
}
def ce_try_finally(builder:ParserBuilder; body:block<():auto(R)>; cleanup:block<():void>) : R {
    var inscope result:R
    try {result <- invoke(body)} recover {
        let message=ce_exception_message()
        invoke(cleanup)
        panic(message)
    }
    try {invoke(cleanup)} recover {parser_rethrow(result)}
    return <- result
}
def ce_using(builder:ParserBuilder; resource:auto(T); body:block<(item:T):auto(R)>; cleanup:block<(var item:T):void>) : R {
    var owner=resource
    var inscope result:R
    try {result <- invoke(body,owner)} recover {
        let message=ce_exception_message()
        invoke(cleanup,owner)
        panic(message)
    }
    try {invoke(cleanup,owner)} recover {parser_rethrow(result)}
    return <- result
}

// Named subgrammar: a function pointer owns no stack captures.
def parser_call(callback:function<(cursor:ParserBuilder):auto(R)>) {
    return (parserFunction=true,callback=callback)
}
def parser_read(builder:ParserBuilder; op:tuple<parserFunction:bool;callback:function<(cursor:ParserBuilder):auto(R)>>) : R {
    return <- invoke(op.callback,builder)
}

struct ParserCommit {_ce_marker:uint8}
def parser_commit() {return ParserCommit()}
def parser_commit(source:auto) {return (parserCut=parserCutTag(),source=source)}
def parser_attempt(source:auto) {return (parserAttempt=parserAttemptTag(),source=source)}
def parser_optional(source:auto) {return (parserOptional=parserOptionalTag(),source=source)}
def parser_many(source:auto) {return (parserRepeat=parserRepeatTag(),source=source,minimum=0)}
def parser_many1(source:auto) {return (parserRepeat=parserRepeatTag(),source=source,minimum=1)}
def parser_sep_by(item,separator:auto) {return (parserSeparated=parserSeparatedTag(),item=item,separator=separator)}

def parser_read(builder:ParserBuilder; op:ParserCommit) {return parser_ok(CeUnit(),builder.position,true)}
def parser_read(builder:ParserBuilder; op:tuple<parserCut:parserCutTag;source:auto(P)>) {
    var inscope result <- parser_read(builder,op.source)
    if(result is failure) {(result as failure).committed=true}
    else {(result as parsed).committed=true}
    return <- result
}
def parser_read(builder:ParserBuilder; op:tuple<parserAttempt:parserAttemptTag;source:auto(P)>) {
    var cursor=builder
    cursor.committed=false
    var inscope result <- parser_read(cursor,op.source)
    if(result is failure && !(result as failure).fatal) {
        (result as failure).committed=builder.committed
        (result as failure).rewound=true
        (result as failure).rewind_position=builder.position
        (result as failure).consumed=false
    }
    if(result is parsed) {(result as parsed).committed = (result as parsed).committed || builder.committed}
    return <- result
}
def private parser_absent(diagnostic:ParseDiagnostic; start:int) {
    return !diagnostic.fatal && !diagnostic.committed && ((!diagnostic.consumed && diagnostic.position==start) || (diagnostic.rewound && diagnostic.rewind_position==start))
}
def parser_read(builder:ParserBuilder; op:tuple<parserOptional:parserOptionalTag;source:auto(P)>) {
    var cursor=builder
    cursor.committed=false
    var inscope result <- parser_read(cursor,op.source)
    var inscope value:variant<some:typedecl((result as parsed).value) -const -&;none:bool>
    if(result is failure) {
        if(!parser_absent(result as failure,builder.position)) {
            var diagnostic=result as failure
            diagnostic.committed = diagnostic.committed || builder.committed
            return <- parser_failure(diagnostic,type<typedecl(value)>)
        }
        value=variant type<typedecl(value)>(none=true)
        return <- parser_ok_move(value,builder.position,builder.committed)
    }
    value as some <- (result as parsed).value
    return <- parser_ok_move(value,(result as parsed).position,builder.committed || (result as parsed).committed)
}
def private parser_progress_diagnostic(builder:ParserBuilder; operationName:string) {
    var result=parser_error(builder,builder.position,"{operationName}: parser succeeded without advancing input",type<CeUnit>)
    var diagnostic=result as failure
    diagnostic.fatal=true
    return diagnostic
}
def parser_read(builder:ParserBuilder; op:tuple<parserRepeat:parserRepeatTag;source:auto(P);minimum:int>) {
    var cursor=builder
    cursor.committed=false
    var inscope values:array<typedecl((parser_read(cursor,op.source) as parsed).value) -const -&>
    var committed=builder.committed
    var failed=false
    var diagnostic:ParseDiagnostic
    try {
        while(true) {
            var inscope result <- parser_read(cursor,op.source)
            if(result is failure) {
                if(length(values)>=op.minimum && parser_absent(result as failure,cursor.position)) {break}
                diagnostic=result as failure
                diagnostic.committed = diagnostic.committed || committed
                failed=true
                break
            }
            if((result as parsed).position<=cursor.position) {
                diagnostic=parser_progress_diagnostic(cursor,op.minimum==0 ? "many" : "many1")
                failed=true
                break
            }
            values |> emplace <| (result as parsed).value
            cursor.position=(result as parsed).position
            committed = committed || (result as parsed).committed
        }
    } recover {parser_rethrow(values)}
    // RC2 JIT cannot return owning CMRES values from inside try/recover.
    if(failed) {return <- parser_failure(diagnostic,type<typedecl(values)>)}
    return <- parser_ok_move(values,cursor.position,committed)
}
def parser_read(builder:ParserBuilder; op:tuple<parserSeparated:parserSeparatedTag;item:auto(P);separator:auto(S)>) {
    var cursor=builder
    cursor.committed=false
    var inscope values:array<typedecl((parser_read(cursor,op.item) as parsed).value) -const -&>
    var committed=builder.committed
    var failed=false
    var diagnostic:ParseDiagnostic
    try {
        while(true) {
            let start=cursor.position
            if(!empty(values)) {
                var inscope separator <- parser_read(cursor,op.separator)
                if(separator is failure) {
                    if(parser_absent(separator as failure,start)) {break}
                    diagnostic=separator as failure
                    diagnostic.committed = diagnostic.committed || committed
                    failed=true
                    break
                }
                cursor.position=(separator as parsed).position
                committed = committed || (separator as parsed).committed
            }
            var inscope item <- parser_read(cursor,op.item)
            if(item is failure) {
                if(parser_absent(item as failure,start)) {break}
                diagnostic=item as failure
                diagnostic.committed = diagnostic.committed || committed
                failed=true
                break
            }
            if((item as parsed).position<=cursor.position) {
                diagnostic=parser_progress_diagnostic(cursor,"sep_by")
                failed=true
                break
            }
            values |> emplace <| (item as parsed).value
            cursor.position=(item as parsed).position
            committed = committed || (item as parsed).committed
        }
    } recover {parser_rethrow(values)}
    if(failed) {return <- parser_failure(diagnostic,type<typedecl(values)>)}
    return <- parser_ok_move(values,cursor.position,committed)
}

def ce_source(builder:ParserBuilder; op:ParserLiteral) {return <- parser_read(builder,op)}

def ce_source(builder:ParserBuilder; op:ParserInteger) {return <- parser_read(builder,op)}

def ce_source(builder:ParserBuilder; op:ParserEnd) {return <- parser_read(builder,op)}

def ce_source(builder:ParserBuilder; op:ParserSpaces) {return <- parser_read(builder,op)}

def ce_source(builder:ParserBuilder; op:ParserCommit) {return <- parser_read(builder,op)}

def ce_source(builder:ParserBuilder; op:tuple<parserAlternatives:parserAlternativesTag;left:auto(L);right:auto(R)>) {return <- parser_read(builder,op)}

def ce_source(builder:ParserBuilder; op:tuple<parserFunction:bool;callback:function<(cursor:ParserBuilder):auto(R)>>) {return <- parser_read(builder,op)}

def ce_source(builder:ParserBuilder; op:tuple<parserCut:parserCutTag;source:auto(P)>) {return <- parser_read(builder,op)}

def ce_source(builder:ParserBuilder; op:tuple<parserAttempt:parserAttemptTag;source:auto(P)>) {return <- parser_read(builder,op)}

def ce_source(builder:ParserBuilder; op:tuple<parserOptional:parserOptionalTag;source:auto(P)>) {return <- parser_read(builder,op)}

def ce_source(builder:ParserBuilder; op:tuple<parserRepeat:parserRepeatTag;source:auto(P);minimum:int>) {return <- parser_read(builder,op)}

def ce_source(builder:ParserBuilder; op:tuple<parserSeparated:parserSeparatedTag;item:auto(P);separator:auto(S)>) {return <- parser_read(builder,op)}
