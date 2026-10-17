options gen2
module validation_builder public
require ./builder_protocol.das public

struct ValidationBuilder {}
struct ValidationErrors {
    messages : string
    count : int
}

def validation_ok(value : auto(T)) : variant<valid:T -const -&;invalid:ValidationErrors> {
    return variant<valid:T -const -&;invalid:ValidationErrors>(valid=value)
}
def validation_error(message : string; unused : type<auto(T)>) : variant<valid:T -const -&;invalid:ValidationErrors> {
    return variant<valid:T -const -&;invalid:ValidationErrors>(invalid=ValidationErrors(messages=message, count=1))
}
// Inputs are already computed. Combine independent failures in left-to-right order.
def validation_zip(left : variant<valid:auto(A);invalid:ValidationErrors>;
                   right : variant<valid:auto(B);invalid:ValidationErrors>) {
    if (left is invalid) {
        var errors = left as invalid
        if (right is invalid) {
            errors.messages += "\n{(right as invalid).messages}"
            errors.count += (right as invalid).count
        }
        return variant<valid:tuple<first:A -const -&;second:B -const -&>;invalid:ValidationErrors>(invalid=errors)
    }
    if (right is invalid) {
        return variant<valid:tuple<first:A -const -&;second:B -const -&>;invalid:ValidationErrors>(invalid=right as invalid)
    }
    return variant<valid:tuple<first:A -const -&;second:B -const -&>;invalid:ValidationErrors>(valid=(first=left as valid, second=right as valid))
}

def ce_protocol(builder : ValidationBuilder) { return CeValueProtocol() }
def ce_unwrap(builder : ValidationBuilder; source : variant<valid:auto(T);invalid:ValidationErrors>) : T {
    return source as valid
}
def ce_return(builder : ValidationBuilder; value : auto(T)) { return validation_ok(value) }
def ce_return_from(builder : ValidationBuilder; source : variant<valid:auto(T);invalid:ValidationErrors>) : variant<valid:T -const -&;invalid:ValidationErrors> { return source }
def ce_zero(builder : ValidationBuilder) { return validation_ok(CeUnit()) }
def ce_bind(builder : ValidationBuilder; source : variant<valid:auto(T);invalid:ValidationErrors>;
            next : block<(value:T):auto(R)>) : R {
    if (source is invalid) { return variant type<R>(invalid=source as invalid) }
    return invoke(next, source as valid)
}
def ce_combine(builder : ValidationBuilder; first : variant<valid:CeUnit;invalid:ValidationErrors>;
               next : block<():auto(R)>) : R {
    if (first is invalid) { return variant type<R>(invalid=first as invalid) }
    return invoke(next)
}
def ce_loop_append(builder : ValidationBuilder; first, step : variant<valid:CeUnit;invalid:ValidationErrors>) {
    if (first is invalid) { return first }
    return step
}
def ce_loop_failed(builder : ValidationBuilder; step : variant<valid:CeUnit;invalid:ValidationErrors>) : bool {
    return step is invalid
}




def ce_merge_sources(builder : ValidationBuilder; left : variant<valid:auto(A);invalid:ValidationErrors>;
                     right : variant<valid:auto(B);invalid:ValidationErrors>) {
    return validation_zip(left, right)
}

def ce_bind_return(builder : ValidationBuilder; source : variant<valid:auto(T);invalid:ValidationErrors>;
                   mapper : block<(value:T):auto(U)>) : variant<valid:U -const -&;invalid:ValidationErrors> {
    if (source is invalid) { return variant<valid:U -const -&;invalid:ValidationErrors>(invalid=source as invalid) }
    return variant<valid:U -const -&;invalid:ValidationErrors>(valid=invoke(mapper, source as valid))
}

def ce_bind2_return(builder:ValidationBuilder;
                    left:variant<valid:auto(A);invalid:ValidationErrors>; right:variant<valid:auto(B);invalid:ValidationErrors>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):auto(U)>) : typedecl(ce_return(builder,default<U>)) {
    if (left is invalid) {
        var errors=left as invalid
        if (right is invalid) { errors.messages+="\n{(right as invalid).messages}"; errors.count+=(right as invalid).count }
        return variant type<typedecl(ce_return(builder,default<U>))>(invalid=errors)
    }
    if (right is invalid) { return variant type<typedecl(ce_return(builder,default<U>))>(invalid=right as invalid) }
    return variant type<typedecl(ce_return(builder,default<U>))>(valid=invoke(mapper,ce_source_pair(left as valid,right as valid)))
}

// Grouped bind: the continuation already returns an outcome.
def ce_bind2(builder:ValidationBuilder;
                    left:variant<valid:auto(A);invalid:ValidationErrors>; right:variant<valid:auto(B);invalid:ValidationErrors>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):auto(R)>) : R {
    if (left is invalid) {
        var errors=left as invalid
        if (right is invalid) { errors.messages+="\n{(right as invalid).messages}"; errors.count+=(right as invalid).count }
        return variant type<R>(invalid=errors)
    }
    if (right is invalid) { return variant type<R>(invalid=right as invalid) }
    return invoke(mapper,ce_source_pair(left as valid,right as valid))
}
