options gen2
module derive_json_runtime public
require ./derive_validation.das public
require daslib/json_boost public

// Decoders append structural errors; validation is a separate second phase.
def derive_json_error(var errors:array<ValidationIssue>;path,message:string;code:string="json_type") {
    validation_add(errors,path,message,code)
}
def derive_json_object(node:JsonValue?;path:string;var errors:array<ValidationIssue>) : bool {
    if(node!=null && node is _object) {return true}
    derive_json_error(errors,path,"expected object")
    return false
}
def derive_json_reset(var value:auto(T)&) {
    static_if(typeinfo can_delete(value)) {delete value}
    static_if(typeinfo can_copy(value)) {value=derive_json_default(type<T -const -&>)}
    else {value <- derive_json_default(type<T -const -&>)}
}
def derive_json_encode(value:string) : JsonValue? {return JV(value)}
def derive_json_encode(value:bool) : JsonValue? {return JV(value)}
def derive_json_encode(value:auto(T)) : JsonValue? {
    static_if(typeinfo is_enum(type<T>)) {
        let info=typeinfo rtti_typeinfo(type<T>)
        for(member in *info.enumType) {
            if(uint64(value)==uint64(member.value)) {return JV(member.name)}
        }
        panic("derive JSON: enum value has no declared name")
        return null
    } static_elif(typeinfo is_variant(type<T>)) {
        var fields:table<string;JsonValue?>
        var node=JV(fields)
        try {
            var tag=JV(derive_variant_name(value));update(node,"case",tag)
            apply(value) $(name:string;field) {var child=_::derive_json_encode(field);update(node,"value",child)}
        } recover {let message="{this_context().last_exception}";delete_json(node);panic(message)}
        return node
    } static_elif(typeinfo is_numeric(type<T>) && !typeinfo is_vector(type<T>)) {
        static_if(typeinfo is_float(type<T>) || typeinfo is_double(type<T>)) {
            if(double(value)-double(value)!=0.0lf) {panic("derive JSON: non-finite number")}
        } else {
            static_if(double(T(-1))>0.0lf) {
                if(uint64(value)>9223372036854775807ul) {panic("derive JSON: integer outside signed JSON int64 range")}
            }
        }
        return JV(value)
    } else {static_assert(false,"derive JSON: unsupported type; use [derive(json=true)] or custom encode/decode overloads");return null}
}
def derive_json_encode(values:array<auto(T)>) : JsonValue? {
    var children:array<JsonValue?>
    var node=JV(children)
    try {
        for(i in range(length(values))) {(node.value as _array) |> push(_::derive_json_encode(values[i]))}
    } recover {let message="{this_context().last_exception}";delete_json(node);panic(message)}
    return node
}
def derive_json_encode(values:auto(T)[]) : JsonValue? {
    var children:array<JsonValue?>
    var node=JV(children)
    try {
        for(i in range(length(values))) {(node.value as _array) |> push(_::derive_json_encode(values[i]))}
    } recover {let message="{this_context().last_exception}";delete_json(node);panic(message)}
    return node
}
def derive_json_decode(node:JsonValue?;var value:string&;path:string;var errors:array<ValidationIssue>) {
    if(node!=null && node is _string) {value=node as _string}
    else {derive_json_error(errors,path,"expected string")}
}
def derive_json_decode(node:JsonValue?;var value:bool&;path:string;var errors:array<ValidationIssue>) {
    if(node!=null && node is _bool) {value=node as _bool}
    else {derive_json_error(errors,path,"expected boolean")}
}
def derive_json_decode(node:JsonValue?;var value:auto(T)&;path:string;var errors:array<ValidationIssue>) {
    static_if(typeinfo is_enum(type<T>)) {
        if(node==null || !(node is _string)) {derive_json_error(errors,path,"expected enum name string");return}
        let info=typeinfo rtti_typeinfo(type<T>)
        for(member in *info.enumType) {
            if(node as _string==member.name) {value=unsafe(reinterpret<T>(member.value));return}
        }
        derive_json_error(errors,path,"unknown enum name","json_enum")
    } static_elif(typeinfo is_variant(type<T>)) {
        derive_json_variant_read(node,value,path,errors,false)
    } static_elif(typeinfo is_numeric(type<T>) && !typeinfo is_vector(type<T>)) {
        static_if(typeinfo is_float(type<T>) || typeinfo is_double(type<T>)) {
            if(node==null || (!(node is _number) && !(node is _longint))) {
                derive_json_error(errors,path,"expected number");return
            }
            let number=node is _number ? node as _number : double(node as _longint)
            let converted=T(number)
            if(number-number!=0.0lf || double(converted)-double(converted)!=0.0lf) {
                derive_json_error(errors,path,"number outside finite field range","json_range");return
            }
            value=converted
        } else {
            if(node==null || !(node is _longint)) {
                if(node!=null && node is _number) {
                    let number=node as _number
                    if(number>=9223372036854775808.0lf || number< -9223372036854775808.0lf) {
                        derive_json_error(errors,path,"integer outside signed JSON int64 range","json_range");return
                    }
                }
                derive_json_error(errors,path,"expected integer in signed JSON int64 range");return
            }
            let number=node as _longint
            let converted=T(number)
            var fits=int64(converted)==number
            static_if(double(T(-1))>0.0lf) {fits=fits && number>=0}
            if(!fits) {derive_json_error(errors,path,"integer outside field range","json_range");return}
            value=converted
        }
    } else {static_assert(false,"derive JSON: unsupported type; use [derive(json=true)] or custom encode/decode overloads")}
}
def derive_json_decode(node:JsonValue?;var values:array<auto(T)>;path:string;var errors:array<ValidationIssue>) {
    if(node==null || !(node is _array)) {derive_json_error(errors,path,"expected array");return}
    derive_json_reset(values)
    values.resize(length(node as _array))
    for(i in range(length(values))) {_::derive_json_decode((node as _array)[i],values[i],"{path}[{i}]",errors)}
}
def derive_json_decode(node:JsonValue?;var values:auto(T)[];path:string;var errors:array<ValidationIssue>) {
    if(node==null || !(node is _array)) {derive_json_error(errors,path,"expected array");return}
    if(length(node as _array)!=length(values)) {derive_json_error(errors,path,"wrong fixed array length","json_length");return}
    for(i in range(length(values))) {_::derive_json_decode((node as _array)[i],values[i],"{path}[{i}]",errors)}
}
// Unannotated scalars/arrays have no validation rules.
def derive_json_validate(value:auto;path:string;var errors:array<ValidationIssue>) {
    static_if(typeinfo is_variant(value)) {apply(value) $(name:string;field) {_::derive_json_validate(field,validation_path(path,"value"),errors)}}
}
def derive_json_validate(values:array<auto(T)>;path:string;var errors:array<ValidationIssue>) {
    for(i in range(length(values))) {_::derive_json_validate(values[i],"{path}[{i}]",errors)}
}
def derive_json_validate(values:auto(T)[];path:string;var errors:array<ValidationIssue>) {
    for(i in range(length(values))) {_::derive_json_validate(values[i],"{path}[{i}]",errors)}
}
def derive_to_json(value:auto) : string {
    var node=_::derive_json_encode(value)
    let previousEmpty=set_no_empty_arrays(false)
    let previousZeros=set_no_trailing_zeros(false)
    {
        return write_json(node)
    } finally {
        set_no_empty_arrays(previousEmpty);set_no_trailing_zeros(previousZeros)
        delete_json(node)
    }
}
[unused_argument(t)]
def derive_from_json(text:string;t:type<auto(T)>;root:string="";limits:JsonReadLimits=JsonReadLimits();strict:bool=false) {
    var inscope result <- (ok=false,value <- derive_json_default(type<T -const -&>),errors <- default<array<ValidationIssue>>)
    var node:JsonValue?
    try {
        var parseError:string
        node=read_json_bounded(text,limits,parseError)
        if(node==null) {derive_json_error(result.errors,root,parseError,"json_parse")}
        else {
            _::derive_json_read(node,result.value,root,result.errors,strict)
            if(length(result.errors)==0) {_::derive_json_validate(result.value,root,result.errors)}
        }
        result.ok=length(result.errors)==0
        if(!result.ok) {derive_json_reset(result.value)}
    } recover {
        let message="{this_context().last_exception}"
        delete_json(node);delete result
        panic(message)
    }
    delete_json(node)
    return <- result
}





// Explicit propagation keeps nested/reentrant loads independent.
def derive_json_read(node:JsonValue?;var value:auto&;path:string;var errors:array<ValidationIssue>;strict:bool) {
    static_if(typeinfo is_variant(value)) {derive_json_variant_read(node,value,path,errors,strict)}
    else {_::derive_json_decode(node,value,path,errors)}
}
def derive_json_read(node:JsonValue?;var values:array<auto(T)>;path:string;var errors:array<ValidationIssue>;strict:bool) {
    if(node==null || !(node is _array)) {derive_json_error(errors,path,"expected array");return}
    derive_json_reset(values);values.resize(length(node as _array))
    for(i in range(length(values))) {_::derive_json_read((node as _array)[i],values[i],"{path}[{i}]",errors,strict)}
}
def derive_json_read(node:JsonValue?;var values:auto(T)[];path:string;var errors:array<ValidationIssue>;strict:bool) {
    if(node==null || !(node is _array)) {derive_json_error(errors,path,"expected array");return}
    if(length(node as _array)!=length(values)) {derive_json_error(errors,path,"wrong fixed array length","json_length");return}
    for(i in range(length(values))) {_::derive_json_read((node as _array)[i],values[i],"{path}[{i}]",errors,strict)}
}
def derive_json_encode(value:$Option<auto(OptionPayload)>) : JsonValue? {
    return value is none ? JVNull() : _::derive_json_encode(value as some)
}
def derive_json_encode(value:$JsonField<auto(FieldPayload)>) : JsonValue? {
    if(value is missing) {panic("derive JSON: missing JsonField has no root/array JSON representation")}
    return value is null_value ? JVNull() : _::derive_json_encode(value as present)
}
def derive_json_write_field(var node:JsonValue?;key:string;value:auto) {
    var child=_::derive_json_encode(value);update(node,key,child)
}
def derive_json_write_field(var node:JsonValue?;key:string;value:$JsonField<auto(FieldPayload)>) {
    if(!(value is missing)) {var child=_::derive_json_encode(value);update(node,key,child)}
}
def derive_json_read(node:JsonValue?;var value:$Option<auto(OptionPayload)>;path:string;var errors:array<ValidationIssue>;strict:bool) {
    derive_json_reset(value)
    if(node!=null && node is _null) {return}
    var initial=derive_json_default(type<OptionPayload -const -&>)
    value <- move_some(initial)
    _::derive_json_read(node,value as some,path,errors,strict)
}
def derive_json_read(node:JsonValue?;var value:$JsonField<auto(FieldPayload)>;path:string;var errors:array<ValidationIssue>;strict:bool) {
    derive_json_reset(value)
    typedef FT=$JsonField<FieldPayload -const -&>
    if(node!=null && node is _null) {value <- variant type<FT>(null_value=JsonNull());return}
    var initial=derive_json_default(type<FieldPayload -const -&>)
    value <- variant type<FT>(present <- initial)
    _::derive_json_read(node,value as present,path,errors,strict)
}
def derive_json_decode(node:JsonValue?;var value:$Option<auto(OptionPayload)>;path:string;var errors:array<ValidationIssue>) {
    derive_json_read(node,value,path,errors,false)
}
def derive_json_decode(node:JsonValue?;var value:$JsonField<auto(FieldPayload)>;path:string;var errors:array<ValidationIssue>) {
    derive_json_read(node,value,path,errors,false)
}
def derive_json_validate(value:$Option<auto(OptionPayload)>;path:string;var errors:array<ValidationIssue>) {
    if(value is some) {_::derive_json_validate(value as some,path,errors)}
}
def derive_json_validate(value:$JsonField<auto(FieldPayload)>;path:string;var errors:array<ValidationIssue>) {
    if(value is present) {_::derive_json_validate(value as present,path,errors)}
}
def derive_json_unknown(var names:array<string>;path:string;var errors:array<ValidationIssue>) {
    sort(names)
    for(name in names) {derive_json_error(errors,validation_path(path,name),"unknown field","json_unknown")}
}
// Convenience overload: fourth bool selects strictness; fourth JsonReadLimits remains compatible.
[unused_argument(t)]
def derive_from_json(text:string;t:type<auto(T)>;root:string;strict:bool) {
    return <- derive_from_json(text,type<T>,root,JsonReadLimits(),strict)
}




def derive_json_variant_read(node:JsonValue?;var value:auto&;path:string;var errors:array<ValidationIssue>;strict:bool) {
    if(!derive_json_object(node,path,errors)) {return}
    if(strict) {
        var inscope unknown:array<string>
        for(key in keys(node as _object)) {if(key!="case" && key!="value") {unknown |> push(key)}}
        derive_json_unknown(unknown,path,errors)
    }
    if(!key_exists(node,"case")) {derive_json_error(errors,validation_path(path,"case"),"missing variant case","json_missing");return}
    let tag=node?["case"]
    if(!(tag is _string)) {derive_json_error(errors,validation_path(path,"case"),"expected variant case string");return}
    derive_variant_select(value,tag as _string,node,path,errors,strict)
}


[unused_argument(t)]
def derive_json_default(t:type<auto(DefaultT)>) {
    static_if(typeinfo is_enum(type<DefaultT>)) {
        let info=typeinfo rtti_typeinfo(type<DefaultT>)
        for(member in *info.enumType) {return unsafe(reinterpret<DefaultT -const -&>(member.value))}
        panic("derive JSON: enum has no members")
        return unsafe(reinterpret<DefaultT -const -&>(0l))
    } else {
        var initial=default<DefaultT -const -&>
        static_if(typeinfo can_copy(initial)) {return initial} else {return <- initial}
    }
}
