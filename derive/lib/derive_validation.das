options gen2
module derive_validation public
require ./derive_runtime.das public
require daslib/rtti

struct ValidationIssue {path:string;message:string;code:string}

def validation_path(parent,field:string) : string {
    return parent=="" ? field : parent+"."+field
}
def validation_add(var errors:array<ValidationIssue>;path,message:string;code:string="custom") {
    errors |> push(ValidationIssue(path=path,message=message,code=code))
}

// Exact comparison of integer values, including mixed signed/unsigned bounds.
def derive_validation_less(a:auto(A);b:auto(B)) : bool {
    static_if(typeinfo is_float(type<A>) || typeinfo is_double(type<A>)) {
        static_assert(typeinfo is_float(type<B>) || typeinfo is_double(type<B>) || typeinfo sizeof(type<B>)<=4,
            "derive validation: float fields require floating or <=32-bit integer bounds")
        return double(a)<double(b)
    } else {
        static_assert(!typeinfo is_float(type<B>) && !typeinfo is_double(type<B>),
            "derive validation: integer fields require integer bounds")
        static_if(double(A(-1))>0.0lf) {
            static_if(double(B(-1))>0.0lf) {return uint64(a)<uint64(b)}
            else {return int64(b)>0 && uint64(a)<uint64(b)}
        } else {
            static_if(double(B(-1))>0.0lf) {return int64(a)<0 || uint64(a)<uint64(b)}
            else {return int64(a)<int64(b)}
        }
    }
}
def derive_check_min(value:auto(T);bound:auto(B);path:string;var errors:array<ValidationIssue>) {
    static_if(typeinfo is_numeric(type<T>) && !typeinfo is_vector(type<T>)) {
        var failed=derive_validation_less(value,bound)
        static_if(typeinfo is_float(type<T>) || typeinfo is_double(type<T>)) {failed=failed || value!=value}
        if(failed) {validation_add(errors,path,"must be >= {bound}","min")}
    } else {static_assert(false,"derive validation: min/max rules require a numeric scalar field")}
}
def derive_check_max(value:auto(T);bound:auto(B);path:string;var errors:array<ValidationIssue>) {
    static_if(typeinfo is_numeric(type<T>) && !typeinfo is_vector(type<T>)) {
        var failed=false
        static_if(typeinfo is_float(type<T>) || typeinfo is_double(type<T>)) {
            static_assert(typeinfo is_float(type<B>) || typeinfo is_double(type<B>) || typeinfo sizeof(type<B>)<=4,
                "derive validation: float fields require floating or <=32-bit integer bounds")
            failed=double(value)>double(bound) || value!=value
        } else {
            static_assert(!typeinfo is_float(type<B>) && !typeinfo is_double(type<B>),
                "derive validation: integer fields require integer bounds")
            failed=derive_validation_less(bound,value)
        }
        if(failed) {validation_add(errors,path,"must be <= {bound}","max")}
    } else {static_assert(false,"derive validation: min/max rules require a numeric scalar field")}
}
// Test string by an explicit overload; arrays and fixed arrays use the generic.
def derive_validation_length(value:string) : int {return length(value)}
def derive_validation_length(value:auto(T)) : int {
    static_if(typeinfo is_array(type<T>) || typeinfo is_dim(type<T>)) {return length(value)}
    else {static_assert(false,"derive validation: length/non_empty rules require a string or array field");return 0}
}
def derive_check_non_empty(value:auto;path:string;var errors:array<ValidationIssue>) {
    if(derive_validation_length(value)==0) {validation_add(errors,path,"must not be empty","non_empty")}
}
def derive_check_min_length(value:auto;bound:int;path:string;var errors:array<ValidationIssue>) {
    if(derive_validation_length(value)<bound) {validation_add(errors,path,"length must be >= {bound}","min_length")}
}
def derive_check_max_length(value:auto;bound:int;path:string;var errors:array<ValidationIssue>) {
    if(derive_validation_length(value)>bound) {validation_add(errors,path,"length must be <= {bound}","max_length")}
}

def derive_validate_into(value:string;path:string;var errors:array<ValidationIssue>) {}
def derive_validate_into(value:bool;path:string;var errors:array<ValidationIssue>) {}
def derive_validate_into(value:auto(T);path:string;var errors:array<ValidationIssue>) {
    static_if((typeinfo is_numeric(type<T>) && !typeinfo is_vector(type<T>)) || typeinfo is_enum(type<T>)) {}
    static_elif(typeinfo is_variant(type<T>)) {
        apply(value) $(name:string;field) {_::derive_validate_into(field,validation_path(path,"value"),errors)}
    }
    else {static_assert(false,"derive validation: nested type requires [derive(validate=true)] or a derive_validate_into overload")}
}
def derive_validate_into(values:array<auto(T)>;path:string;var errors:array<ValidationIssue>) {
    for(i in range(length(values))) {_::derive_validate_into(values[i],"{path}[{i}]",errors)}
}
def derive_validate_into(values:auto(T)[];path:string;var errors:array<ValidationIssue>) {
    for(i in range(length(values))) {_::derive_validate_into(values[i],"{path}[{i}]",errors)}
}
def derive_validate(value:auto;root:string="") : array<ValidationIssue> {
    var inscope errors:array<ValidationIssue>
    try {_::derive_validate_into(value,root,errors)} recover {
        let message="{this_context().last_exception}"
        delete errors
        panic(message)
    }
    return <- errors
}


def derive_validate_into(value:$Option<auto(OptionPayload)>;path:string;var errors:array<ValidationIssue>) {
    if(value is some) {_::derive_validate_into(value as some,path,errors)}
}
def derive_validate_into(value:$JsonField<auto(FieldPayload)>;path:string;var errors:array<ValidationIssue>) {
    if(value is present) {_::derive_validate_into(value as present,path,errors)}
}

def derive_check_min(value:$Option<auto(OptionPayload)>;bound:auto;path:string;var errors:array<ValidationIssue>) {
    if(value is some) {_::derive_check_min(value as some,bound,path,errors)}
}

def derive_check_max(value:$Option<auto(OptionPayload)>;bound:auto;path:string;var errors:array<ValidationIssue>) {
    if(value is some) {_::derive_check_max(value as some,bound,path,errors)}
}

def derive_check_non_empty(value:$Option<auto(OptionPayload)>;path:string;var errors:array<ValidationIssue>) {
    if(value is some) {_::derive_check_non_empty(value as some,path,errors)}
}

def derive_check_min_length(value:$Option<auto(OptionPayload)>;bound:int;path:string;var errors:array<ValidationIssue>) {
    if(value is some) {_::derive_check_min_length(value as some,bound,path,errors)}
}

def derive_check_max_length(value:$Option<auto(OptionPayload)>;bound:int;path:string;var errors:array<ValidationIssue>) {
    if(value is some) {_::derive_check_max_length(value as some,bound,path,errors)}
}

def derive_check_min(value:$JsonField<auto(FieldPayload)>;bound:auto;path:string;var errors:array<ValidationIssue>) {
    if(value is present) {_::derive_check_min(value as present,bound,path,errors)}
}

def derive_check_max(value:$JsonField<auto(FieldPayload)>;bound:auto;path:string;var errors:array<ValidationIssue>) {
    if(value is present) {_::derive_check_max(value as present,bound,path,errors)}
}

def derive_check_non_empty(value:$JsonField<auto(FieldPayload)>;path:string;var errors:array<ValidationIssue>) {
    if(value is present) {_::derive_check_non_empty(value as present,path,errors)}
}

def derive_check_min_length(value:$JsonField<auto(FieldPayload)>;bound:int;path:string;var errors:array<ValidationIssue>) {
    if(value is present) {_::derive_check_min_length(value as present,bound,path,errors)}
}

def derive_check_max_length(value:$JsonField<auto(FieldPayload)>;bound:int;path:string;var errors:array<ValidationIssue>) {
    if(value is present) {_::derive_check_max_length(value as present,bound,path,errors)}
}
