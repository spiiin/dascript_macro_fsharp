options gen2
module derive_runtime public
require strings
require daslib/rtti
require daslib/apply
require ./derive_variant_macros.das public
require ./derive_types.das public

// Combine value hashes in field/element order. Not a persistent file format.
def derive_hash_combine(seed,value:uint64) : uint64 {
    return (seed ^ value)*1099511628211ul
}
def derive_debug(value:string) : string {return "\"{escape(value)}\""}
def derive_debug(value:bool) : string {return value ? "true" : "false"}
def derive_equal(a,b:string) : bool {return a==b}
def derive_equal(a,b:bool) : bool {return a==b}
def derive_hash(value:string) : uint64 {
    var result=14695981039346656037ul
    for(byte in value) {result=derive_hash_combine(result,uint64(byte))}
    return result
}
// SplitMix64 finalizer for scalar bit patterns; arithmetic is unsigned/wrapping.
def derive_hash_bits(bits:uint64) : uint64 {
    var result=bits+0x9e3779b97f4a7c15ul
    result=(result ^ (result >> 30))*0xbf58476d1ce4e5b9ul
    result=(result ^ (result >> 27))*0x94d049bb133111ebul
    return result ^ (result >> 31)
}
def derive_hash(value:bool) : uint64 {return derive_hash_bits(value ? 1ul : 0ul)}

def derive_debug(value:auto(T)) : string {
    static_if((typeinfo is_numeric(type<T>) && !typeinfo is_vector(type<T>)) || typeinfo is_enum(type<T>)) {
        return "{value}"
    } static_elif(typeinfo is_variant(type<T>)) {
        var text=derive_variant_name(value)
        apply(value) $(name:string;field) {text+="("+_::derive_debug(field)+")"}
        return text
    } else {
        static_assert(false,"derive_debug: unsupported value; annotate nested structs with [derive] or provide an overload")
        return ""
    }
}
def derive_equal(a,b:auto(T)) : bool {
    static_if(typeinfo typename(a)!=typeinfo typename(b)) {
        static_assert(false,"derive_equal requires matching types")
        return false
    } static_elif((typeinfo is_numeric(type<T>) && !typeinfo is_vector(type<T>)) || typeinfo is_enum(type<T>)) {
        return a==b
    } static_elif(typeinfo is_variant(type<T>)) {
        if(variant_index(a)!=variant_index(b)) {return false}
        derive_variant_equal(a,b)
        return false
    } else {
        static_assert(false,"derive_equal: unsupported value; annotate nested structs with [derive] or provide an overload")
        return false
    }
}
def derive_hash(value:auto(T)) : uint64 {
    static_if((typeinfo is_numeric(type<T>) && !typeinfo is_vector(type<T>)) || typeinfo is_enum(type<T>)) {
        static_if(typeinfo is_float(type<T>)) {
            // IEEE equality considers +0 and -0 equal. Their hashes must agree.
            if(value==0) {return derive_hash_bits(0ul)}
            return derive_hash_bits(uint64(unsafe(reinterpret<uint>(value))))
        } static_elif(typeinfo is_double(type<T>)) {
            if(value==0) {return derive_hash_bits(0ul)}
            return derive_hash_bits(unsafe(reinterpret<uint64>(value)))
        } else {
            return derive_hash_bits(uint64(value))
        }
    } static_elif(typeinfo is_variant(type<T>)) {
        var result=derive_hash(derive_variant_name(value))
        apply(value) $(name:string;field) {result=derive_hash_combine(result,_::derive_hash(field))}
        return result
    } else {
        static_assert(false,"derive_hash: unsupported value; annotate nested structs with [derive] or provide an overload")
        return 0ul
    }
}

def derive_debug(values:array<auto(T)>) : string {
    var text="["
    for(i in range(length(values))) {
        if(i!=0) {text+=", "}
        text+=_::derive_debug(values[i])
    }
    return text+"]"
}
def derive_debug(values:auto(T)[]) : string {
    var text="["
    for(i in range(length(values))) {
        if(i!=0) {text+=", "}
        text+=_::derive_debug(values[i])
    }
    return text+"]"
}
def derive_equal(a,b:array<auto(T)>) : bool {
    if(length(a)!=length(b)) {return false}
    for(i in range(length(a))) {if(!_::derive_equal(a[i],b[i])) {return false}}
    return true
}
def derive_equal(a,b:auto(T)[]) : bool {
    if(length(a)!=length(b)) {return false}
    for(i in range(length(a))) {if(!_::derive_equal(a[i],b[i])) {return false}}
    return true
}
def derive_hash(values:array<auto(T)>) : uint64 {
    var result=derive_hash_combine(14695981039346656037ul,uint64(length(values)))
    for(i in range(length(values))) {result=derive_hash_combine(result,_::derive_hash(values[i]))}
    return result
}
def derive_hash(values:auto(T)[]) : uint64 {
    var result=derive_hash_combine(14695981039346656037ul,uint64(length(values)))
    for(i in range(length(values))) {result=derive_hash_combine(result,_::derive_hash(values[i]))}
    return result
}


def derive_debug(value:$Option<auto(OptionPayload)>) : string {
    return value is none ? "None" : "Some("+_::derive_debug(value as some)+")"
}
def derive_equal(a,b:$Option<auto(OptionPayload)>) : bool {
    if(a is none) {return b is none}
    return b is some && _::derive_equal(a as some,b as some)
}
def derive_hash(value:$Option<auto(OptionPayload)>) : uint64 {
    return value is none ? derive_hash_bits(0ul) : derive_hash_combine(derive_hash_bits(1ul),_::derive_hash(value as some))
}
def derive_debug(value:$JsonField<auto(FieldPayload)>) : string {
    if(value is missing) {return "Missing"}
    if(value is null_value) {return "Null"}
    return "Present("+_::derive_debug(value as present)+")"
}
def derive_equal(a,b:$JsonField<auto(FieldPayload)>) : bool {
    if(a is missing) {return b is missing}
    if(a is null_value) {return b is null_value}
    return b is present && _::derive_equal(a as present,b as present)
}
def derive_hash(value:$JsonField<auto(FieldPayload)>) : uint64 {
    if(value is missing) {return derive_hash_bits(0ul)}
    if(value is null_value) {return derive_hash_bits(1ul)}
    return derive_hash_combine(derive_hash_bits(2ul),_::derive_hash(value as present))
}

def derive_variant_name(value:auto) : string {
    let info=typeinfo rtti_typeinfo(value)
    let index=variant_index(value)
    if(index<0 || index>=int(info.argCount)) {panic("derive: invalid variant tag")}
    return unsafe(info.argNames[index])
}

// Clone is opt-in on structs; built-in containers dispatch to user overloads.
def derive_clone(value:string) : string {return value}
def derive_clone(value:bool) : bool {return value}
def derive_clone(value:JsonNull) : JsonNull {return JsonNull()}

def derive_clone(value:auto(T)) : T -const -& {
    static_if((typeinfo is_numeric(type<T>) && !typeinfo is_vector(type<T>)) || typeinfo is_enum(type<T>)) {
        return value
    } static_elif(typeinfo is_variant(type<T>)) {
        derive_variant_clone(value)
    } else {
        static_assert(false,"derive_clone: unsupported value; use [derive(clone=true)] on nested structs or provide an overload")
    }
}

def derive_clone(values:array<auto(T)>) : array<T> {
    var result:array<T>
    try {
        for(i in range(length(values))) {
            static_if(typeinfo can_copy(values[i])) {result |> push(_::derive_clone(values[i]))}
            else {
                var item <- _::derive_clone(values[i])
                result |> emplace(item)
            }
        }
    } recover {
        let message="{this_context().last_exception}"
        delete result
        panic(message)
    }
    return <- result
}

def derive_clone(values:auto(T)[]) {
    // The same zeroed-storage idiom as builtin clone_to_move; no element initializers.
    unsafe {
        var result:typedecl(values) -const -&
        try {
            for(i in range(length(values))) {
                static_if(typeinfo can_copy(values[i])) {result[i]=_::derive_clone(values[i])}
                else {
                    static_if(typeinfo can_delete(result[i])) {delete result[i]}
                    result[i] <- _::derive_clone(values[i])
                }
            }
        } recover {
            let message="{this_context().last_exception}"
            static_if(typeinfo can_delete(result)) {delete result}
            panic(message)
        }
        static_if(typeinfo can_copy(result)) {return result}
        else {return <- result}
    }
}
