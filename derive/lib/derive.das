options gen2
module derive public
require ./derive_runtime.das public
require ./derive_diff.das public
require ./derive_patch.das public
require ./derive_builder.das public
require ./derive_schema.das public
require ./derive_optics.das public
require ./derive_validation.das public
require ./derive_json_runtime.das public
require daslib/ast
require strings
require daslib/ast_boost
require daslib/templates_boost

def derive_validation_identifier(name:string) : bool {
    if(length(name)==0) {return false}
    for(c,i in name,range(length(name))) {
        if(!((c>=65 && c<=90) || (c>=97 && c<=122) || c==95 || (i>0 && c>=48 && c<=57))) {return false}
    }
    return true
}
def derive_rule_is_number(value:RttiValue) : bool {
    return value is tInt || value is tUInt || value is tInt64 || value is tUInt64 || value is tFloat || value is tDouble
}
def derive_rule_expr(value:RttiValue) : ExpressionPtr {
    if(value is tInt) {return qmacro($v(value as tInt))}
    elif(value is tUInt) {return qmacro($v(value as tUInt))}
    elif(value is tInt64) {return qmacro($v(value as tInt64))}
    elif(value is tUInt64) {return qmacro($v(value as tUInt64))}
    elif(value is tFloat) {return qmacro($v(value as tFloat))}
    elif(value is tDouble) {return qmacro($v(value as tDouble))}
    return null
}
def derive_rule_real(value:RttiValue) : double {
    if(value is tInt) {return double(value as tInt)}
    elif(value is tUInt) {return double(value as tUInt)}
    elif(value is tInt64) {return double(value as tInt64)}
    elif(value is tUInt64) {return double(value as tUInt64)}
    elif(value is tFloat) {return double(value as tFloat)}
    return value as tDouble
}
def derive_rule_signed(value:RttiValue) : int64 {
    return value is tInt ? int64(value as tInt) : value as tInt64
}
def derive_rule_unsigned(value:RttiValue) : uint64 {
    return value is tUInt ? uint64(value as tUInt) : value as tUInt64
}
def derive_rule_greater(a,b:RttiValue) : bool {
    if(a is tFloat || a is tDouble || b is tFloat || b is tDouble) {return derive_rule_real(a)>derive_rule_real(b)}
    let au=a is tUInt || a is tUInt64
    let bu=b is tUInt || b is tUInt64
    if(au && bu) {return derive_rule_unsigned(a)>derive_rule_unsigned(b)}
    if(!au && !bu) {return derive_rule_signed(a)>derive_rule_signed(b)}
    if(au) {let rhs=derive_rule_signed(b);return rhs<0 || derive_rule_unsigned(a)>uint64(rhs)}
    let lhs=derive_rule_signed(a)
    return lhs>=0 && uint64(lhs)>derive_rule_unsigned(b)
}

[structure_macro(name="derive")]
class Derive : AstStructureAnnotation {
    def override apply(var st:StructurePtr; var group:ModuleGroup;
                       args:AnnotationArgumentList; var errors:das_string) : bool {
        if(st.flags.isClass || st.parent!=null) {
            errors:="[derive] only plain structs without inheritance are supported"
            return false
        }
        var seen:table<string;bool>
        var debug=true
        var equality=true
        var hashing=true
        var building=false
        var patching=false
        var diffing=false
        var cloning=false
        var validation=false
        var json=false
        var checkName=""
        for(arg in args) {
            let name=string(arg.name)
            if(key_exists(seen,name)) {
                errors:="[derive] duplicate option '{name}'"
                return false
            }
            seen[name]=true
            if(name=="check") {
                let option=find_arg(args,name)
                if(!(option is tString) || !derive_validation_identifier(option as tString)) {
                    errors:="[derive] check must be a simple function name string"
                    return false
                }
                checkName=option as tString
                continue
            }
            if(name!="debug" && name!="equality" && name!="hash" && name!="validate" && name!="json" && name!="clone" && name!="diff" && name!="patch" && name!="builder") {
                errors:="[derive] unknown option '{name}'; expected debug, equality, hash, clone, diff, patch, builder, validate, json or check"
                return false
            }
            let option=find_arg(args,name)
            if(!(option is tBool)) {
                errors:="[derive] option '{name}' must be bool"
                return false
            }
            if(name=="builder") {building=option as tBool}
            elif(name=="debug") {debug=option as tBool}
            elif(name=="equality") {equality=option as tBool}
            elif(name=="hash") {hashing=option as tBool}
            elif(name=="patch") {patching=option as tBool}
            elif(name=="diff") {diffing=option as tBool}
            elif(name=="clone") {cloning=option as tBool}
            elif(name=="validate") {validation=option as tBool}
            else {json=option as tBool}
        }
        if(building && !validation) {errors:="[derive] builder requires validate=true";return false}
        if(patching && (!cloning || !equality || !validation)) {
            errors:="[derive] patch requires clone=true, equality=true and validate=true"
            return false
        }
        if(diffing && !debug) {
            errors:="[derive] diff requires debug for diagnostic snapshots; use debug=true"
            return false
        }
        if(hashing && !equality) {
            errors:="[derive] hash requires equality; use equality=true or hash=false"
            return false
        }
        if(checkName!="" && !validation) {
            errors:="[derive] check requires validate=true"
            return false
        }
        if(!debug && !equality && !hashing && !validation && !json && !cloning && !diffing && !patching && !building) {
            errors:="[derive] enable at least one operation"
            return false
        }
        var builderDefaults:array<ExpressionPtr>
        var builderChecks:array<ExpressionPtr>
        var builderSteps:array<ExpressionPtr>
        var patchSteps:array<ExpressionPtr>
        var diffSteps:array<ExpressionPtr>
        var cloneSteps:array<ExpressionPtr>
        var debugSteps:array<ExpressionPtr>
        var equalSteps:array<ExpressionPtr>
        var hashSteps:array<ExpressionPtr>
        var validateSteps:array<ExpressionPtr>
        var encodeSteps:array<ExpressionPtr>
        var decodeSteps:array<ExpressionPtr>
        var jsonValidationSteps:array<ExpressionPtr>
        var jsonNames:table<string;bool>
        var knownKeys:array<ExpressionPtr>
        var first=true
        for(field in st.fields) {
            let name=string(field.name)
            var builderRequired=false
            var builderSeen=false
            for(annotation in field.annotation) {
                let rule=string(annotation.name)
                if(!starts_with(rule,"builder_")) {continue}
                if(!building) {errors:="[derive] field '{name}': builder rules require builder=true";return false}
                if(rule!="builder_required") {errors:="[derive] field '{name}': unknown builder rule '{rule}'";return false}
                if(builderSeen) {errors:="[derive] field '{name}': duplicate builder_required";return false}
                builderSeen=true
                let option=get_annotation_argument_value(annotation)
                if(!(option is tBool)) {errors:="[derive] field '{name}': builder_required must be bool";return false}
                builderRequired=option as tBool
            }
            if(building) {
                let ftDefault=field._type
                var initial=field.init!=null ? clone_expression(field.init) : qmacro(default<$t(ftDefault)>)
                builderDefaults |> push <| qmacro_expr() {{
                    static_if(typeinfo can_copy(value.$f(name))) {value.$f(name)=$e(initial)}
                    else {value.$f(name) <- $e(initial)}
                }}
                if(builderRequired) {
                    builderChecks |> push <| qmacro_expr() {
                        if(!key_exists(draft.supplied,$v(name))) {validation_add(result.errors,validation_path(root,$v(name)),"missing required field","builder_required")}
                    }
                }
                builderSteps |> push <| qmacro_expr() {
                    if(key_exists(draft.supplied,$v(name))) {
                        static_if(typeinfo can_copy(value.$f(name))) {value.$f(name)=_::derive_clone(draft.data.$f(name))}
                        else {
                            var replacement <- _::derive_clone(draft.data.$f(name))
                            static_if(typeinfo can_delete(value.$f(name))) {delete value.$f(name)}
                            value.$f(name) <- replacement
                        }
                    }
                }
                let setter="builder_"+name
                let mover="builder_move_"+name
                let ft=field._type
                var fn=qmacro_function(setter) $(var draft:$DerivedBuilder<$t(st)>;input:$t(ft)) {
                    static_if(typeinfo can_copy(input)) {draft.data.$f(name)=_::derive_clone(input)}
                    else {
                        var replacement <- _::derive_clone(input)
                        static_if(typeinfo can_delete(draft.data.$f(name))) {delete draft.data.$f(name)}
                        draft.data.$f(name) <- replacement
                    }
                    draft.supplied[$v(name)]=true
                }
                fn.flags.generated=true;add_function(st._module,fn)
                var mv=qmacro_function(mover) $(var draft:$DerivedBuilder<$t(st)>;var input:$t(ft)) {
                    // Mark presence before consuming input; table growth can throw.
                    draft.supplied[$v(name)]=true
                    static_if(typeinfo can_copy(input)) {draft.data.$f(name)=input}
                    else {
                        static_if(typeinfo can_delete(draft.data.$f(name))) {delete draft.data.$f(name)}
                        draft.data.$f(name) <- input
                    }
                }
                mv.flags.generated=true;add_function(st._module,mv)
            }
            var fieldChecks:array<ExpressionPtr>
            var ruleSeen:table<string;bool>
            var minimum:RttiValue
            var maximum:RttiValue
            var minLength=-1
            var maxLength=-1
            var hasMin=false
            var hasMax=false
            for(annotation in field.annotation) {
                let rule=string(annotation.name)
                if(!starts_with(rule,"validate_")) {continue}
                if(!validation) {errors:="[derive] field '{name}': validation rules require validate=true";return false}
                if(key_exists(ruleSeen,rule)) {errors:="[derive] field '{name}': duplicate rule '{rule}'";return false}
                ruleSeen[rule]=true
                let option=get_annotation_argument_value(annotation)
                if(rule=="validate_check" || rule=="validate_each" || rule=="validate_unique_by") {
                    if(!(option is tString) || !derive_validation_identifier(option as tString)) {
                        errors:="[derive] field '{name}': {rule} must be a simple function name string";return false
                    }
                    let callback=option as tString
                    if(rule=="validate_check") {
                        fieldChecks |> push <| qmacro_expr() {{
                            static_assert(typeinfo is_void($c(callback)(value.$f(name),fieldPath,errors)),"derive validation: field check must return void")
                            $c(callback)(value.$f(name),fieldPath,errors)
                        }}
                    } elif(rule=="validate_each") {
                        fieldChecks |> push <| qmacro_expr() {{
                            static_if(typeinfo is_array(value.$f(name)) || typeinfo is_dim(value.$f(name))) {
                                for(index in range(length(value.$f(name)))) {
                                    let itemPath="{fieldPath}[{index}]"
                                    static_assert(typeinfo is_void($c(callback)(value.$f(name)[index],itemPath,errors)),"derive validation: element check must return void")
                                    $c(callback)(value.$f(name)[index],itemPath,errors)
                                }
                            } else {static_assert(false,"derive validation: validate_each requires an array or fixed array field")}
                        }}
                    } else {
                        fieldChecks |> push <| qmacro_expr() {{
                            static_if(typeinfo is_array(value.$f(name)) || typeinfo is_dim(value.$f(name))) {
                                var inscope keys:array<typedecl($c(callback)(value.$f(name)[0])) -const -&>
                                try {
                                    for(index in range(length(value.$f(name)))) {
                                        static_if(typeinfo can_copy($c(callback)(value.$f(name)[index]))) {
                                            keys |> push($c(callback)(value.$f(name)[index]))
                                        } else {
                                            var key <- $c(callback)(value.$f(name)[index])
                                            keys |> emplace(key)
                                        }
                                        for(previousIndex in range(index)) {
                                            if(_::derive_equal(keys[index],keys[previousIndex])) {
                                                validation_add(errors,"{fieldPath}[{index}]","duplicate key; first occurrence at {fieldPath}[{previousIndex}]","unique")
                                                break
                                            }
                                        }
                                    }
                                } recover {
                                    let message="{this_context().last_exception}"
                                    delete keys
                                    panic(message)
                                }
                            } else {static_assert(false,"derive validation: validate_unique_by requires an array or fixed array field")}
                        }}
                    }
                } elif(rule=="validate_min" || rule=="validate_max") {
                    if(!derive_rule_is_number(option)) {errors:="[derive] field '{name}': {rule} must be a number";return false}
                    let bound=derive_rule_expr(option)
                    if(rule=="validate_min") {
                        minimum=option;hasMin=true
                        fieldChecks |> push <| qmacro_expr() {derive_check_min(value.$f(name),$e(bound),fieldPath,errors)}
                    } else {
                        maximum=option;hasMax=true
                        fieldChecks |> push <| qmacro_expr() {derive_check_max(value.$f(name),$e(bound),fieldPath,errors)}
                    }
                } elif(rule=="validate_non_empty") {
                    if(!(option is tBool)) {errors:="[derive] field '{name}': validate_non_empty must be bool";return false}
                    if(option as tBool) {fieldChecks |> push <| qmacro_expr() {derive_check_non_empty(value.$f(name),fieldPath,errors)}}
                } elif(rule=="validate_min_length" || rule=="validate_max_length") {
                    if(!(option is tInt) || option as tInt<0) {errors:="[derive] field '{name}': {rule} must be a nonnegative int";return false}
                    let bound=option as tInt
                    if(rule=="validate_min_length") {
                        minLength=bound
                        fieldChecks |> push <| qmacro_expr() {derive_check_min_length(value.$f(name),$v(bound),fieldPath,errors)}
                    } else {
                        maxLength=bound
                        fieldChecks |> push <| qmacro_expr() {derive_check_max_length(value.$f(name),$v(bound),fieldPath,errors)}
                    }
                } else {errors:="[derive] field '{name}': unknown validation rule '{rule}'";return false}
            }
            if(hasMin && hasMax && derive_rule_greater(minimum,maximum)) {errors:="[derive] field '{name}': min must be <= max";return false}
            if(minLength>=0 && maxLength>=0 && minLength>maxLength) {errors:="[derive] field '{name}': min_length must be <= max_length";return false}
            var jsonName=name
            var jsonSkip=false
            var jsonRequired=true
            var requiredSet=false
            var defaultSet=false
            var jsonDefault:RttiValue
            var jsonSeen:table<string;bool>
            for(annotation in field.annotation) {
                let key=string(annotation.name)
                if(!starts_with(key,"json_")) {continue}
                if(!json) {errors:="[derive] field '{name}': JSON rules require json=true";return false}
                if(key_exists(jsonSeen,key)) {errors:="[derive] field '{name}': duplicate JSON rule '{key}'";return false}
                jsonSeen[key]=true
                let option=get_annotation_argument_value(annotation)
                if(key=="json_name") {
                    if(!(option is tString) || length(option as tString)==0) {errors:="[derive] field '{name}': json_name must be a nonempty string";return false}
                    jsonName=option as tString
                } elif(key=="json_skip" || key=="json_required") {
                    if(!(option is tBool)) {errors:="[derive] field '{name}': {key} must be bool";return false}
                    if(key=="json_skip") {jsonSkip=option as tBool}
                    else {jsonRequired=option as tBool;requiredSet=true}
                } elif(key=="json_default") {
                    if(!derive_rule_is_number(option) && !(option is tString) && !(option is tBool)) {errors:="[derive] field '{name}': json_default must be a scalar literal";return false}
                    jsonDefault=option;defaultSet=true
                } else {errors:="[derive] field '{name}': unknown JSON rule '{key}'";return false}
            }
            if(defaultSet && requiredSet && jsonRequired) {errors:="[derive] field '{name}': json_default conflicts with json_required=true";return false}
            if(json && !jsonSkip) {
                if(key_exists(jsonNames,jsonName)) {errors:="[derive] duplicate JSON field name '{jsonName}'";return false}
                jsonNames[jsonName]=true
                knownKeys |> push <| qmacro_expr() {if(key==$v(jsonName)) {known=true}}
                encodeSteps |> push <| qmacro_expr() {derive_json_write_field(node,$v(jsonName),value.$f(name))}
                var missing:array<ExpressionPtr>
                if(defaultSet) {
                    var expr:ExpressionPtr
                    if(jsonDefault is tString) {expr=qmacro($v(jsonDefault as tString))}
                    elif(jsonDefault is tBool) {expr=qmacro($v(jsonDefault as tBool))}
                    else {expr=derive_rule_expr(jsonDefault)}
                    missing |> push <| qmacro_expr() {value.$f(name)=$e(expr)}
                } elif(jsonRequired) {
                    missing |> push <| qmacro_expr() {derive_json_error(errors,fieldPath,"missing required field","json_missing")}
                }
                var step=qmacro_expr() {{
                    let fieldPath=validation_path(path,$v(jsonName))
                    if(key_exists(node,$v(jsonName))) {derive_json_read(node?[$v(jsonName)],value.$f(name),fieldPath,errors,strict)}
                    else {$b(missing)}
                }}
                step |> force_at(field.at)
                decodeSteps |> push(step)
            }
            var validate=qmacro_expr() {{
                let fieldPath=validation_path(path,$v(json && !jsonSkip ? jsonName : name))
                $b(fieldChecks)
                derive_validate_into(value.$f(name),fieldPath,errors)
            }}
            validate |> force_at(field.at)
            validateSteps |> push(validate)
            jsonValidationSteps |> push <| qmacro_expr() {derive_json_validate(value.$f(name),validation_path(path,$v(json && !jsonSkip ? jsonName : name)),errors)}
            var patchStep=qmacro_expr() {
                _::derive_patch_into(current.$f(name),expected.$f(name),desired.$f(name),validation_path(path,$v(name)),errors)
            }
            patchStep |> force_at(field.at)
            patchSteps |> push(patchStep)
            var diffStep=qmacro_expr() {
                _::derive_diff_into(before.$f(name),after.$f(name),diff_path(path,$v(name)),changes)
            }
            diffStep |> force_at(field.at)
            diffSteps |> push(diffStep)
            var cloneStep=qmacro_expr() {{
                static_if(typeinfo can_copy(value.$f(name))) {
                    result.$f(name)=_::derive_clone(value.$f(name))
                } else {
                    static_if(typeinfo can_delete(result.$f(name))) {delete result.$f(name)}
                    result.$f(name) <- _::derive_clone(value.$f(name))
                }
            }}
            cloneStep |> force_at(field.at)
            cloneSteps |> push(cloneStep)
            let prefix=(first ? "" : ", ")+name+"="
            first=false
            var dbg=qmacro_expr() {text+=$v(prefix)+derive_debug(value.$f(name))}
            var eq=qmacro_expr() {if(!derive_equal(left.$f(name),right.$f(name))) {return false}}
            var hs=qmacro_expr() {result=derive_hash_combine(result,derive_hash(value.$f(name)))}
            dbg |> force_at(field.at);eq |> force_at(field.at);hs |> force_at(field.at)
            debugSteps |> push(dbg);equalSteps |> push(eq);hashSteps |> push(hs)
        }
        let title=string(st.name)
        if(building) {
            var fn=qmacro_function("derive_build") $(draft:$DerivedBuilder<$t(st)>;root:string="") {
                static_assert(typeinfo sizeof(type<$t(st)>)>0,"derive_builder: zero-sized root types are unsupported by SDK Option AOT")
                var result <- derive_builder_empty_result(type<$t(st)>)
                try {
                    $b(builderChecks)
                    if(length(result.errors)==0) {
                        // Run native defaults once per attempted build, after presence checks.
                        unsafe {
                            var value:$t(st)
                            try {
                                $b(builderDefaults)
                                $b(builderSteps)
                                _::derive_validate_into(value,root,result.errors)
                                if(length(result.errors)==0) {
                                    static_if(typeinfo can_copy(value)) {result.value=some(value)}
                                    else {
                                        result.value <- move_some(value)
                                        // SDK AOT can copy a variant payload without clearing move_some's input.
                                        // Ownership is now in result; never finalize the stale source payload.
                                        memzero(value)
                                    }
                                    result.ok=true
                                }
                            } recover {
                                let message="{this_context().last_exception}"
                                static_if(typeinfo can_delete(value)) {delete value}
                                panic(message)
                            }
                            static_if(typeinfo can_delete(value)) {delete value}
                        }
                    }
                } recover {
                    let message="{this_context().last_exception}"
                    delete result;panic(message)
                }
                return <- result
            }
            fn.flags.generated=true;add_function(st._module,fn)
        }
        if(debug) {
            var fn=qmacro_function("derive_debug") $(value:$t(st)) : string {
                var text=$v(title)+"\{"
                $b(debugSteps)
                return text+"\}"
            }
            fn.flags.generated=true
            add_function(st._module,fn)
        }
        if(equality) {
            var fn=qmacro_function("derive_equal") $(left,right:$t(st)) : bool {
                $b(equalSteps)
                return true
            }
            fn.flags.generated=true
            add_function(st._module,fn)
        }
        if(hashing) {
            var fn=qmacro_function("derive_hash") $(value:$t(st)) : uint64 {
                var result=derive_hash($v(title))
                $b(hashSteps)
                return result
            }
            fn.flags.generated=true
            add_function(st._module,fn)
        }
        if(patching) {
            var fn=qmacro_function("derive_patch_into") $(var current:$t(st);expected,desired:$t(st);path:string;var errors:array<ValidationIssue>) {
                $b(patchSteps)
            }
            fn.flags.generated=true;add_function(st._module,fn)
        }
        if(diffing) {
            var fn=qmacro_function("derive_diff_into") $(before,after:$t(st);path:string;var changes:array<DiffChange>) {
                $b(diffSteps)
            }
            fn.flags.generated=true;add_function(st._module,fn)
        }
        if(cloning) {
            var fn=qmacro_function("derive_clone") $(value:$t(st)) : $t(st) {
                // As in builtin clone_to_move: start with zeroed storage, not native initializers.
                unsafe {
                    var result:$t(st)
                    try {$b(cloneSteps)} recover {
                        let message="{this_context().last_exception}"
                        static_if(typeinfo can_delete(result)) {delete result}
                        panic(message)
                    }
                    static_if(typeinfo can_copy(result)) {return result}
                    else {return <- result}
                }
            }
            fn.flags.generated=true;add_function(st._module,fn)
        }
        if(validation) {
            if(checkName!="") {
                validateSteps |> push <| qmacro_expr() {{
                    static_assert(typeinfo is_void($c(checkName)(value,path,errors)),"derive validation: custom check must return void")
                    $c(checkName)(value,path,errors)
                }}
            }
            var fn=qmacro_function("derive_validate_into") $(value:$t(st);path:string;var errors:array<ValidationIssue>) {
                $b(validateSteps)
            }
            fn.flags.generated=true
            add_function(st._module,fn)
        }
        if(json) {
            var encoder=qmacro_function("derive_json_encode") $(value:$t(st)) : JsonValue? {
                var fields:table<string;JsonValue?>
                var node=JV(fields)
                try {$b(encodeSteps)} recover {
                    let message="{this_context().last_exception}"
                    delete_json(node);panic(message)
                }
                return node
            }
            encoder.flags.generated=true;add_function(st._module,encoder)
            var decoder=qmacro_function("derive_json_read") $(node:JsonValue?;var value:$t(st);path:string;var errors:array<ValidationIssue>;strict:bool) {
                if(!derive_json_object(node,path,errors)) {return}
                if(strict) {
                    var inscope unknown:array<string>
                    for(key in keys(node as _object)) {
                        var known=false
                        $b(knownKeys)
                        if(!known) {unknown |> push(key)}
                    }
                    derive_json_unknown(unknown,path,errors)
                }
                $b(decodeSteps)
            }
            decoder.flags.generated=true;add_function(st._module,decoder)
            var legacy=qmacro_function("derive_json_decode") $(node:JsonValue?;var value:$t(st);path:string;var errors:array<ValidationIssue>) {
                derive_json_read(node,value,path,errors,false)
            }
            legacy.flags.generated=true;add_function(st._module,legacy)
            var validationBody:array<ExpressionPtr>
            if(validation) {validationBody |> push <| qmacro_expr() {derive_validate_into(value,path,errors)}}
            else {validationBody <- jsonValidationSteps}
            var validator=qmacro_function("derive_json_validate") $(value:$t(st);path:string;var errors:array<ValidationIssue>) {
                $b(validationBody)
            }
            validator.flags.generated=true;add_function(st._module,validator)
        }
        return true
    }
}
