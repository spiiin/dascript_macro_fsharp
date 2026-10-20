options gen2
module derive_patch public
require ./derive_validation.das public
require daslib/rtti
require daslib/templates
require daslib/templates_boost
require daslib/typemacro_boost

[template_tuple(T)]
struct template TypedPatch {expected:T;desired:T}

[template(t)]
def derive_patch_empty_result(t:auto(T)) {
    static_if(typeinfo can_copy(type<T>)) {
        return <- (ok=false,value=none(type<T -const -&>),errors <- default<array<ValidationIssue>>)
    } else {
        return <- (ok=false,value <- none(type<T -const -&>),errors <- default<array<ValidationIssue>>)
    }
}
def derive_patch_some_clone(value:auto(T)) : $Option<T -const -&> {
    static_if(typeinfo can_copy(value)) {return some(_::derive_clone(value))}
    else {
        var cloned <- _::derive_clone(value)
        return <- move_some(cloned)
    }
}
def derive_make_patch(expected,desired:auto(T)) : $TypedPatch<T -const -&> {
    static_assert(typeinfo sizeof(expected)>0,"derive_patch: zero-sized root types are unsupported by SDK Option AOT; add a data field to the root model")
    static_assert(typeinfo typename(expected)==typeinfo typename(desired),"derive_make_patch requires matching types")
    // As in Clone: zeroed storage avoids running model initializers.
    unsafe {
        var patch:$TypedPatch<T -const -&>
        try {
            static_if(typeinfo can_copy(expected)) {
                patch.expected=_::derive_clone(expected)
                patch.desired=_::derive_clone(desired)
            } else {
                patch.expected <- _::derive_clone(expected)
                patch.desired <- _::derive_clone(desired)
            }
        } recover {
            let message="{this_context().last_exception}"
            static_if(typeinfo can_delete(patch)) {delete patch}
            panic(message)
        }
        static_if(typeinfo can_copy(patch)) {return patch}
        else {return <- patch}
    }
}
def derive_apply_patch(current:auto(T);patch:$TypedPatch<T -const -&>;root:string="") {
    static_assert(typeinfo sizeof(current)>0,"derive_patch: zero-sized root types are unsupported by SDK Option AOT; add a data field to the root model")
    var result <- derive_patch_empty_result(type<T -const -&>)
    try {
        static_if(typeinfo can_copy(current)) {result.value=derive_patch_some_clone(current)}
        else {result.value <- derive_patch_some_clone(current)}
        _::derive_patch_into(result.value as some,patch.expected,patch.desired,root,result.errors)
        if(length(result.errors)==0) {_::derive_validate_into(result.value as some,root,result.errors)}
        if(length(result.errors)==0) {result.ok=true}
        else {
            static_if(typeinfo can_delete(result.value)) {delete result.value}
            static_if(typeinfo can_copy(current)) {result.value=none(type<T -const -&>)}
            else {result.value <- none(type<T -const -&>)}
        }
    } recover {
        let message="{this_context().last_exception}"
        delete result
        panic(message)
    }
    return <- result
}
def derive_apply_patch_to(var current:auto(T)&;patch:$TypedPatch<T -const -&>;root:string="") : array<ValidationIssue> {
    var inscope result <- derive_apply_patch(current,patch,root)
    if(result.ok) {
        static_if(typeinfo can_copy(current)) {current=result.value as some}
        else {
            static_if(typeinfo can_delete(current)) {delete current}
            current <- result.value as some
        }
    }
    return <- result.errors
}
def derive_patch_conflict(path:string;var errors:array<ValidationIssue>) {
    validation_add(errors,path,"current value differs from patch expectation","patch_conflict")
}
def derive_patch_replace(var current:auto(T)&;expected,desired:T;path:string;var errors:array<ValidationIssue>) {
    if(_::derive_equal(expected,desired)) {return}
    if(!_::derive_equal(current,expected)) {derive_patch_conflict(path,errors);return}
    static_if(typeinfo can_copy(current)) {current=_::derive_clone(desired)}
    else {
        var replacement <- _::derive_clone(desired)
        static_if(typeinfo can_delete(current)) {delete current}
        current <- replacement
    }
}
def derive_patch_into(var current:string&;expected,desired:string;path:string;var errors:array<ValidationIssue>) {
    derive_patch_replace(current,expected,desired,path,errors)
}
def derive_patch_into(var current:bool&;expected,desired:bool;path:string;var errors:array<ValidationIssue>) {
    derive_patch_replace(current,expected,desired,path,errors)
}
def derive_patch_into(var current:auto(T)&;expected,desired:T;path:string;var errors:array<ValidationIssue>) {
    static_if((typeinfo is_numeric(type<T>) && !typeinfo is_vector(type<T>)) || typeinfo is_enum(type<T>)) {
        derive_patch_replace(current,expected,desired,path,errors)
    } static_elif(typeinfo is_variant(type<T>)) {
        let expectedCase=derive_variant_name(expected)
        let desiredCase=derive_variant_name(desired)
        let currentCase=derive_variant_name(current)
        if(_::derive_equal(expected,desired)) {return}
        if(expectedCase!=desiredCase) {derive_patch_replace(current,expected,desired,path,errors)}
        elif(currentCase!=expectedCase) {derive_patch_conflict(path,errors)}
        else {derive_variant_patch(current,expected,desired,path,errors)}
    } else {
        static_assert(false,"derive_patch: unsupported value; use [derive(clone=true,validate=true,patch=true)] on nested structs or provide a derive_patch_into overload")
    }
}
def derive_patch_into(var current:array<auto(T)>&;expected,desired:array<T>;path:string;var errors:array<ValidationIssue>) {
    derive_patch_replace(current,expected,desired,path,errors)
}
def derive_patch_into(var current:auto(T)[]&;expected,desired:T[];path:string;var errors:array<ValidationIssue>) {
    derive_patch_replace(current,expected,desired,path,errors)
}
def derive_patch_into(var current:$Option<auto(OptionPayload)>&;expected,desired:$Option<OptionPayload>;path:string;var errors:array<ValidationIssue>) {
    if(_::derive_equal(expected,desired)) {return}
    if(variant_index(expected)!=variant_index(desired)) {derive_patch_replace(current,expected,desired,path,errors)}
    elif(variant_index(current)!=variant_index(expected)) {derive_patch_conflict(path,errors)}
    elif(current is some) {_::derive_patch_into(current as some,expected as some,desired as some,path,errors)}
}
def derive_patch_into(var current:$JsonField<auto(FieldPayload)>&;expected,desired:$JsonField<FieldPayload>;path:string;var errors:array<ValidationIssue>) {
    if(_::derive_equal(expected,desired)) {return}
    if(variant_index(expected)!=variant_index(desired)) {derive_patch_replace(current,expected,desired,path,errors)}
    elif(variant_index(current)!=variant_index(expected)) {derive_patch_conflict(path,errors)}
    elif(current is present) {_::derive_patch_into(current as present,expected as present,desired as present,path,errors)}
}
