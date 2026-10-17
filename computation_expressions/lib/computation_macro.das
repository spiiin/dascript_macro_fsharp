options gen2
module computation_macro public
require ./builder_protocol.das public
require ./sequence_runtime.das public
require ./zip_runtime.das public
require ./resumable_lowering.das
require daslib/ast
require daslib/ast_boost
require daslib/templates_boost

// Preserve expression reference-ness; standard is_ref includes all ref types.
[typeinfo_macro(name="ce_source_is_borrowed")]
class CeSourceBorrowed : AstTypeInfoMacro {
    def override getAstChange(expr : ExprTypeInfo?; var errors : das_string) : ExpressionPtr {
        if (expr.subexpr == null || expr.subexpr._type == null) {
            errors := "computation: source type must be inferred"
            return null
        }
        // Const array parameters can be ExprVar without the explicit ref flag.
        // A named variable still belongs to its caller; only temporaries move here.
        return <- new ExprConstBool(at=expr.at, value=expr.subexpr._type.flags.ref || (expr.subexpr is ExprVar))
    }
}

// Resolve the optional Source hook without an identity function copying/moving input.
[typeinfo_macro(name="ce_resolved_source")]
class CeResolvedSource : AstTypeInfoMacro {
    def override getAstChange(expr:ExprTypeInfo?; var errors:das_string) : ExpressionPtr {
        if (expr.subexpr==null || expr.subexpr._type==null || !(expr.subexpr is ExprCall)) {
            errors := "computation: source hook must be inferred"
            return null
        }
        let call=expr.subexpr as ExprCall
        let t=call._type
        if (t.baseType==Type.tVoid) {
            errors := "computation: ce_source must return a source, not void"
            return null
        }
        if (t.baseType==Type.tStructure && t.structType.name=="CeSourceFallback"
                && t.structType._module.name=="builder_protocol") {
            return clone_expression(call.arguments[1])
        }
        return clone_expression(call)
    }
}
def ce_normalize_source(builder:string; source:ExpressionPtr) : ExpressionPtr {
    if(source is ExprCall) {
        let call=source as ExprCall
        if((call.name=="state_modify" || call.name=="state_gets") && length(call.arguments)==1) {
            var applied=qmacro(ce_state_modify($i(builder),$e(call.arguments[0])))
            if(call.name=="state_gets") {applied=qmacro(ce_state_gets($i(builder),$e(call.arguments[0])))}
            applied.at=source.at
            return applied
        }
    }
    var result=qmacro(typeinfo ce_resolved_source(ce_source($i(builder),$e(source))))
    result.at=source.at
    return result
}
def ce_return_from_source(builder:string; source:ExpressionPtr; collect:bool; owned:bool=false) : ExpressionPtr {
    let normalized=ce_normalize_source(builder,source)
    let name=make_unique_private_name("__ce_return_source",source.at)
    var next=qmacro($($i(name):typedecl($e(normalized))) {
        return ce_return_from($i(builder),$i(name))
    })
    if (collect) {
        next=qmacro($($i(name):typedecl($e(normalized))) {
            return <- ce_return_from($i(builder),$i(name))
        })
    }
    if (owned) {((next as ExprMakeBlock)._block as ExprBlock).arguments[0]._type.flags.constant=false}
    return ce_source_apply(normalized,next,true,collect)
}
def ce_normalize_for(builder:string; statement:ExpressionPtr) : ExpressionPtr {
    var result=clone_expression(statement) as ExprFor
    for (source in result.sources) {source=ce_normalize_source(builder,source)}
    return result
}

// and_bind is a source-tree marker, consumed only immediately under bind.
var private ce_merge_locations : table<string;ExpressionPtr>
[typeinfo_macro(name="ce_checked_merge")]
class CeCheckedMerge : AstTypeInfoMacro {
    def override getAstChange(expr:ExprTypeInfo?; var errors:das_string) : ExpressionPtr {
        if(expr.subexpr==null || expr.subexpr._type==null) {errors:="computation: and_bind source types must be inferred";return null}
        let envelope=expr.subexpr as ExprCall
        let merged=envelope.arguments[0]
        let t=merged._type
        if(t.baseType==Type.tStructure && t.structType.name=="CeMergeSourcesFallback"
                && t.structType._module.name=="builder_protocol") {
            let location=string((envelope.arguments[2] as ExprConstString).value)
            errors:="computation: and_bind is unsupported for builder {describe(envelope.arguments[1]._type)} and these sources at {location}; define ce_merge_sources(builder, left, right) or use sequential bind"
            if(key_exists(ce_merge_locations,location)) {
                let message=string(errors)
                var failure=qmacro(static_assert(false,$v(message)))
                failure.at=ce_merge_locations[location].at
                var left=clone_expression(merged)
                if(length(envelope.arguments)==4) {left=clone_expression(envelope.arguments[3])}
                elif(merged is ExprCall) {left=clone_expression((merged as ExprCall).arguments[1])}
                var invalid=qmacro(invoke($ {
                    $e(failure);
                    static_if(typeinfo can_copy($e(left))) {return $e(left)}
                    else {return <- $e(left)}
                }))
                invalid.at=ce_merge_locations[location].at
                let originBody=((invalid as ExprInvoke).arguments[0] as ExprMakeBlock)._block as ExprBlock
                var assertion=clone_expression(originBody.list[0])
                assertion.at=ce_merge_locations[location].at
                (((invalid as ExprInvoke).arguments[0] as ExprMakeBlock)._block as ExprBlock).list[0]=assertion
                errors := ""
                return invalid
            }
            return null
        }
        return clone_expression(merged)
    }
}
def ce_merge_source(node : ExpressionPtr; builder : string; var error : string&) : ExpressionPtr {
    if (node is ExprCall && (node as ExprCall).name == "and_bind") {
        let call = node as ExprCall
        if (length(call.arguments) != 2) {
            error = "computation: expected 'left |> and_bind(right) |> bind'"
            return null
        }
        var left = ce_merge_source(call.arguments[0], builder, error)
        if (!empty(error)) { return null }
        var right = ce_merge_source(call.arguments[1], builder, error)
        if (!empty(error)) { return null }
        let location="{node.at.fileInfo.name}:{int(node.at.line)}:{int(node.at.column)}"
        ce_merge_locations |> insert(location,new ExprConstBool(at=node.at,value=true))
        var merged = qmacro(typeinfo ce_checked_merge(ce_merge_origin(ce_merge_sources($i(builder), $e(left), $e(right)), $i(builder), $v(location))))
        merged.at = node.at
        return merged
    }
    return ce_normalize_source(builder,node)
}

// Resumable sources transfer ownership before suspension. Materialize each
// product once. Save exceptions before running any source finalizer, outside
// recover, so a close callback cannot replace the original factory error.
def ce_resumable_merge_source(node:ExpressionPtr; builder:string; var error:string&) : ExpressionPtr {
    if(!(node is ExprCall) || (node as ExprCall).name!="and_bind") {return ce_normalize_source(builder,node)}
    let call=node as ExprCall
    if(length(call.arguments)!=2) {error="computation: expected 'left |> and_bind(right) |> bind'";return null}
    let left=ce_resumable_merge_source(call.arguments[0],builder,error)
    let right=ce_resumable_merge_source(call.arguments[1],builder,error)
    if(!empty(error)) {return null}
    let ln=make_unique_private_name("__await_left",node.at)
    let rn=make_unique_private_name("__await_right",node.at)
    let result=make_unique_private_name("__await_product",node.at)
    let failure=result+"_error"
    let failed=result+"_failed"
    let location="{node.at.fileInfo.name}:{int(node.at.line)}:{int(node.at.column)}"
    ce_merge_locations |> insert(location,new ExprConstBool(at=node.at,value=true))
    let merged=qmacro(ce_merge_sources($i(builder),$i(ln),$i(rn)))
    let checked=qmacro(typeinfo ce_checked_merge(ce_merge_origin($i(result),$i(builder),$v(location),$i(ln))))
    let closeLeft=qmacro_expr() {static_if(typeinfo can_delete($i(ln))) {delete $i(ln)}}
    let closeRight=qmacro_expr() {static_if(typeinfo can_delete($i(rn))) {delete $i(rn)}}
    let closeResult=qmacro_expr() {static_if(typeinfo can_delete($i(result))) {delete $i(result)}}
    // These are explicit owners, not inscope: cleanup must run after the primary
    // exception is saved, and a returned product already owns both children.
    return qmacro(invoke($ {
        var $i(ln):typedecl($e(left))
        static_if(typeinfo can_copy($e(left))) {$i(ln)=$e(left)}
        else {$i(ln) <- $e(left)}
        var $i(rn):typedecl($e(right))
        var $i(failure)=""
        var $i(failed)=false
        try {
            static_if(typeinfo can_copy($e(right))) {$i(rn)=$e(right)}
            else {$i(rn) <- $e(right)}
        } recover {$i(failed)=true;$i(failure)=ce_exception_message()}
        if($i(failed)) {$e(closeLeft);$e(closeRight);panic($i(failure))}
        var $i(result):typedecl($e(merged))
        try {
            static_if(typeinfo can_copy($e(merged))) {$i(result)=$e(merged)}
            else {$i(result) <- $e(merged)}
        } recover {$i(failed)=true;$i(failure)=ce_exception_message()}
        $e(closeLeft);$e(closeRight)
        if($i(failed)) {$e(closeResult);panic($i(failure))}
        return <- $e(checked)
    }))
}

// Run a continuation while keeping an owned temporary alive. Borrowed arrays
// remain borrowed; factories and intermediate products are released on panic too.
def ce_source_apply(source, next : ExpressionPtr; collect : bool; move_result:bool=true) : ExpressionPtr {
    if (!collect) { return qmacro(invoke($e(next), $e(source))) }
    let ownedName = make_unique_private_name("__ce_owned_source", source.at)
    let resultName = ownedName + "_result"
    if (!move_result) {
        return qmacro(invoke($ {
            static_if ((typeinfo can_copy($e(source))) || (typeinfo ce_source_is_borrowed($e(source)))) {
                return invoke($e(next), $e(source))
            } else {
                var inscope $i(ownedName) <- $e(source)
                var $i(resultName) : typedecl(invoke($e(next), $i(ownedName)))
                try { $i(resultName) = invoke($e(next), $i(ownedName)) } recover { ce_owned_source_rethrow($i(ownedName)) }
                return $i(resultName)
            }
        }))
    }
    return qmacro(invoke($ {
        static_if ((typeinfo can_copy($e(source))) || (typeinfo ce_source_is_borrowed($e(source)))) {
            return <- invoke($e(next), $e(source))
        } else {
            var inscope $i(ownedName) <- $e(source)
            var inscope $i(resultName) : typedecl(invoke($e(next), $i(ownedName)))
            try { $i(resultName) <- invoke($e(next), $i(ownedName)) } recover { ce_owned_source_rethrow($i(ownedName)) }
            return <- $i(resultName)
        }
    }))
}

def ce_merge_apply(node : ExpressionPtr; builder : string; next : ExpressionPtr;
                   collect : bool; var error : string&; mapper : ExpressionPtr = null; ordinary : ExpressionPtr = null; owned:bool=false) : ExpressionPtr {
    if (node is ExprCall && (node as ExprCall).name == "and_bind") {
        let call = node as ExprCall
        if (length(call.arguments)!=2) {
            error = "computation: expected 'left |> and_bind(right) |> bind'"
            return null
        }
        var leftType = ce_merge_source(call.arguments[0], builder, error)
        var rightType = ce_merge_source(call.arguments[1], builder, error)
        if (!empty(error)) { return null }
        let leftName = make_unique_private_name("__ce_merge_left", node.at)
        let rightName = make_unique_private_name("__ce_merge_right", node.at)
        let location="{node.at.fileInfo.name}:{int(node.at.line)}:{int(node.at.column)}"
        ce_merge_locations |> insert(location,new ExprConstBool(at=node.at,value=true))
        var merged = qmacro(typeinfo ce_checked_merge(ce_merge_origin(ce_merge_sources($i(builder), $i(leftName), $i(rightName)), $i(builder), $v(location))))
        merged.at = node.at
        var mergeBody = ce_source_apply(merged, next, true, collect)
        if (ordinary != null) {
            mergeBody = ce_bind2_continuation(builder, qmacro($i(leftName)), qmacro($i(rightName)), ordinary, mergeBody, collect)
        }
        if (mapper != null) {
            mergeBody = ce_bind2_application(builder, qmacro($i(leftName)), qmacro($i(rightName)), mapper, mergeBody, collect)
        }
        var rightNext = qmacro($($i(rightName):typedecl($e(rightType))) { return $e(mergeBody) })
        if (collect) { rightNext = qmacro($($i(rightName):typedecl($e(rightType))) { return <- $e(mergeBody) }) }
        if (owned) {((rightNext as ExprMakeBlock)._block as ExprBlock).arguments[0]._type.flags.constant=false}
        var rightBody = ce_merge_apply(call.arguments[1], builder, rightNext, collect, error, null, null, owned)
        var leftNext = qmacro($($i(leftName):typedecl($e(leftType))) { return $e(rightBody) })
        if (collect) { leftNext = qmacro($($i(leftName):typedecl($e(leftType))) { return <- $e(rightBody) }) }
        if (owned) {((leftNext as ExprMakeBlock)._block as ExprBlock).arguments[0]._type.flags.constant=false}
        return ce_merge_apply(call.arguments[0], builder, leftNext, collect, error, null, null, owned)
    }
    return ce_source_apply(ce_normalize_source(builder,node), next, true, collect)
}

[typeinfo_macro(name="ce_has_bind_return")]
class CeHasBindReturn : AstTypeInfoMacro {
    def override getAstChange(expr:ExprTypeInfo?; var errors:das_string) : ExpressionPtr {
        if (expr.subexpr==null || expr.subexpr._type==null) { errors := "computation: BindReturn type must be inferred"; return null }
        let t=expr.subexpr._type
        let fallback=(t.baseType==Type.tStructure && t.structType.name=="CeBindReturnFallback"
                      && t.structType._module.name=="builder_protocol")
        return <- new ExprConstBool(at=expr.at,value=!fallback)
    }
}

def ce_bind_application(builder:string; source, mapper, ordinary:ExpressionPtr; fused, collect:bool) : ExpressionPtr {
    if (!fused) { return qmacro(ce_bind($i(builder), $e(source), $e(ordinary))) }
    if (collect) {
        return qmacro(invoke($ {
            static_if (typeinfo ce_has_bind_return(ce_bind_return($i(builder), $e(source), $e(mapper)))) {
                return <- ce_bind_return($i(builder), $e(source), $e(mapper))
            } else {
                return <- ce_bind($i(builder), $e(source), $e(ordinary))
            }
        }))
    }
    return qmacro(invoke($ {
        static_if (typeinfo ce_has_bind_return(ce_bind_return($i(builder), $e(source), $e(mapper)))) {
            return ce_bind_return($i(builder), $e(source), $e(mapper))
        } else {
            return ce_bind($i(builder), $e(source), $e(ordinary))
        }
    }))
}

def ce_bind2_application(builder:string; left, right, mapper, fallback:ExpressionPtr; collect:bool) : ExpressionPtr {
    if (collect) {
        return qmacro(invoke($ {
            static_if (typeinfo ce_has_bind_return(ce_bind2_return($i(builder), $e(left), $e(right), $e(mapper)))) {
                return <- ce_bind2_return($i(builder), $e(left), $e(right), $e(mapper))
            } else { return <- $e(fallback) }
        }))
    }
    return qmacro(invoke($ {
        static_if (typeinfo ce_has_bind_return(ce_bind2_return($i(builder), $e(left), $e(right), $e(mapper)))) {
            return ce_bind2_return($i(builder), $e(left), $e(right), $e(mapper))
        } else { return $e(fallback) }
    }))
}

def ce_bind2_continuation(builder:string; left, right, mapper, fallback:ExpressionPtr; collect:bool) : ExpressionPtr {
    if (collect) {
        return qmacro(invoke($ {
            static_if (typeinfo ce_has_bind_return(ce_bind2($i(builder), $e(left), $e(right), $e(mapper)))) {
                return <- ce_bind2($i(builder), $e(left), $e(right), $e(mapper))
            } else { return <- $e(fallback) }
        }))
    }
    return qmacro(invoke($ {
        static_if (typeinfo ce_has_bind_return(ce_bind2($i(builder), $e(left), $e(right), $e(mapper)))) {
            return ce_bind2($i(builder), $e(left), $e(right), $e(mapper))
        } else { return $e(fallback) }
    }))
}

// Optional loop methods are selected without evaluating source/condition/body.
[typeinfo_macro(name="ce_has_loop")]
class CeHasLoop : AstTypeInfoMacro {
    def override getAstChange(expr:ExprTypeInfo?; var errors:das_string) : ExpressionPtr {
        if (expr.subexpr==null || expr.subexpr._type==null) { errors := "computation: loop result type must be inferred"; return null }
        let t=expr.subexpr._type
        if (t.baseType==Type.tVoid) { errors := "computation: loop hook must return a builder outcome"; return null }
        return <- new ExprConstBool(at=expr.at,value=!ce_is_protocol(t,"CeLoopFallback"))
    }
}

[typeinfo_macro(name="ce_for_ref_iterator")]
class CeForRefIterator : AstTypeInfoMacro {
    def override getAstChange(expr:ExprTypeInfo?; var errors:das_string) : ExpressionPtr {
        if (expr.subexpr==null || expr.subexpr._type==null) { errors := "computation: for source type must be inferred"; return null }
        let t=expr.subexpr._type
        let mutableRef=t.baseType==Type.tIterator && t.firstType.flags.ref && !t.firstType.flags.constant
        return <- new ExprConstBool(at=expr.at,value=mutableRef)
    }
}

def ce_loop_dispatch(custom, fallback:ExpressionPtr; collect:bool) : ExpressionPtr {
    if (collect) {
        return qmacro(invoke($ {
            static_if (typeinfo ce_has_loop($e(custom))) { return <- $e(custom) }
            else { return <- $e(fallback) }
        }))
    }
    return qmacro(invoke($ {
        static_if (typeinfo ce_has_loop($e(custom))) { return $e(custom) }
        else { return $e(fallback) }
    }))
}

def ce_for_application(builder:string; source, callback, fallback:ExpressionPtr;
                        collect_mode, mutable_source:bool; at:LineInfo) : ExpressionPtr {
    var custom=qmacro(ce_for($i(builder),$e(source),$e(callback)))
    let sourceName=make_unique_private_name("__ce_for_source",at)
    var apply=qmacro($(var $i(sourceName):typedecl($e(source))) {
        return ce_for($i(builder),$i(sourceName),$e(callback))
    })
    if (collect_mode) {
        apply=qmacro($(var $i(sourceName):typedecl($e(source))) {
            return <- ce_for($i(builder),$i(sourceName),$e(callback))
        })
    }
    if (!mutable_source) {
        if (collect_mode) {
            apply=qmacro($($i(sourceName):typedecl($e(source))) { return <- ce_for($i(builder),$i(sourceName),$e(callback)) })
        } else {
            apply=qmacro($($i(sourceName):typedecl($e(source))) { return ce_for($i(builder),$i(sourceName),$e(callback)) })
        }
    }
    var owned=ce_source_apply(source,apply,true,collect_mode)
    // Iterators are consumed by the hook; ordinary source temporaries
    // are scoped here, while source variables stay borrowed.
    var execution=qmacro(invoke($ {
        static_if (typeinfo is_iterator($e(source))) { return $e(custom) }
        else { return $e(owned) }
    }))
    if (collect_mode) {
        execution=qmacro(invoke($ {
            static_if (typeinfo is_iterator($e(source))) { return <- $e(custom) }
            else { return <- $e(owned) }
        }))
    }
    // Probe the raw call: fallback markers must not own/evaluate sources.
    if (collect_mode) {
        return qmacro(invoke($ {
            static_if (typeinfo ce_has_loop($e(custom))) { return <- $e(execution) }
            else { return <- $e(fallback) }
        }))
    } else {
        return qmacro(invoke($ {
            static_if (typeinfo ce_has_loop($e(custom))) { return $e(execution) }
            else { return $e(fallback) }
        }))
    }
}

// Evaluate sources left-to-right in nested scopes. Borrowed sources keep their
// references; temporary collections stay alive until all zip iterators close.
def ce_zip_source_scopes(original:ExprFor?; body:ExpressionPtr; names:array<string>; index:int) : ExpressionPtr {
    if (index==length(original.sources)) { return clone_expression(body) }
    let source=original.sources[index]
    let name=names[index]
    var rest=ce_zip_source_scopes(original,body,names,index+1)
    var mutableNext=qmacro($(var $i(name):typedecl($e(source))) { return $e(rest) })
    var constantNext=qmacro($($i(name):typedecl($e(source))) { return $e(rest) })
    var mutableCall=ce_source_apply(source,mutableNext,true,false)
    var constantCall=ce_source_apply(source,constantNext,true,false)
    return qmacro(invoke($ {
        static_if (typeinfo is_const($e(source))) { return $e(constantCall) }
        else { return $e(mutableCall) }
    }))
}

[typeinfo_macro(name="ce_zip_value")]
class CeZipValue : AstTypeInfoMacro {
    def override getAstChange(expr:ExprTypeInfo?; var errors:das_string) : ExpressionPtr {
        if (expr.subexpr==null || expr.subexpr._type==null) { errors := "zip: cursor type must be inferred"; return null }
        let cursor=expr.subexpr
        let element=cursor._type.argTypes[0].firstType
        var access=qmacro($e(cursor).slot)
        if (element.flags.ref) {access=qmacro(*$e(cursor).slot); access.genFlags.alwaysSafe=true}
        let mode=cursor._type.argTypes[2]
        if (mode.structType.name=="CeZipReadOnly" && mode.structType._module.name=="zip_runtime") {
            var constantAccess=qmacro(reinterpret<typedecl($e(access)) const&>($e(access)))
            constantAccess.genFlags.alwaysSafe=true
            return constantAccess
        }
        return access
    }
}

// Explicit cursor storage remains accessible when next() or the consumer panics.
def ce_zip_traversal(original:ExprFor?; names:array<string>; iteration:ExpressionPtr; visitor:string; directBody:ExpressionPtr) : ExpressionPtr {
    var declarations:array<ExpressionPtr>
    var initialize:array<ExpressionPtr>
    var advance:array<ExpressionPtr>
    var aliases:array<ExpressionPtr>
    var cleanup:array<ExpressionPtr>
    let first=make_unique_private_name("__ce_zip_first",original.at)
    let more=make_unique_private_name("__ce_zip_more",original.at)
    let message=make_unique_private_name("__ce_zip_error",original.at)
    for (index in range(length(names))) {
        let source=names[index]
        let cursor=make_unique_private_name("__ce_zip_cursor_{index}",original.at)
        let item=string(original.iterators[index])
        declarations |> push <| qmacro_expr() {var $i(cursor):typedecl(ce_zip_cursor($i(source)))}
        initialize |> push <| qmacro_expr() {$i(cursor) <- ce_zip_cursor($i(source))}
        advance |> push <| qmacro_expr() {
            if (!ce_zip_next($i(cursor))) {
                $i(more)=false
                if (!$i(first)) {break}
            }
        }
        var binding=qmacro_expr() {var $i(item) & = typeinfo ce_zip_value($i(cursor))} as ExprLet
        binding.variables[0]._type.flags.removeConstant=false
        binding.variables[0]._type.flags.constant=false
        aliases |> push <| binding
        cleanup |> push <| qmacro_expr() {ce_zip_close($i(cursor),$i(message))}
    }
    var consume:ExprBlock?
    if (directBody!=null) {consume=clone_expression(directBody) as ExprBlock}
    else {consume=qmacro_block() {if (!invoke($i(visitor),$e(iteration))) {break}} as ExprBlock}
    for (statement in consume.list) {aliases |> push <| clone_expression(statement)}
    consume.list |> clear()
    for (statement in aliases) {consume.list |> push <| clone_expression(statement)}
    var execute=qmacro($ {
        var $i(message)=""
        try {
            $b(initialize)
            var $i(first)=true
            while (true) {
                var $i(more)=true
                $b(advance)
                $i(first)=false
                if (!$i(more)) {break}
                $e(consume)
            }
        } recover { $i(message)=ce_zip_exception() }
        $b(cleanup)
        if (!empty($i(message))) {panic($i(message))}
        return true
    })
    var executeBlock=(execute as ExprMakeBlock)._block as ExprBlock
    for (statement in executeBlock.list) {declarations |> push <| clone_expression(statement)}
    executeBlock.list |> clear()
    for (statement in declarations) {executeBlock.list |> push <| clone_expression(statement)}
    return qmacro(invoke($e(execute)))
}



// Removing moved-from temporary slots is observable for user finalizers.
// Keep the old path for such element types, including nested fields/containers.
def ce_sink_safe_element(t:TypeDeclPtr; depth:int=0) : bool {
    if(t==null || depth>32) {return false}
    if(t.baseType==Type.tHandle || t.baseType==Type.tPointer || t.baseType==Type.tIterator || t.baseType==Type.tLambda) {return false}
    if(t.baseType==Type.tStructure) {
        if(t.structType.flags.isClass) {return false}
        var userFinalizer=false
        for_each_module_no_order(compiling_program().get_ptr(),$(mod) {
            for_each_function(mod,"finalize") $(fn) {
                if(!fn.flags.generated && length(fn.arguments)==1 && fn.arguments[0]._type.baseType==Type.tStructure && fn.arguments[0]._type.structType==t.structType) {userFinalizer=true}
            }
            if(mod.name!="builtin") {
                for_each_generic(mod,"finalize") $(fn) {if(!fn.flags.generated) {userFinalizer=true}}
            }
        })
        if(userFinalizer) {return false}
        for(field in t.structType.fields) {if(!ce_sink_safe_element(field._type,depth+1)) {return false}}
    }
    if(t.firstType!=null && !ce_sink_safe_element(t.firstType,depth+1)) {return false}
    if(t.secondType!=null && !ce_sink_safe_element(t.secondType,depth+1)) {return false}
    for(arg in t.argTypes) {if(!ce_sink_safe_element(arg,depth+1)) {return false}}
    return true
}

[typeinfo_macro(name="ce_has_collect_sink")]
class CeHasCollectSink : AstTypeInfoMacro {
    def override getAstChange(expr:ExprTypeInfo?; var errors:das_string) : ExpressionPtr {
        if (expr.subexpr==null || expr.subexpr._type==null) {errors := "computation: collect sink descriptor must be inferred";return null}
        let t=expr.subexpr._type
        let enabled=t.baseType==Type.tTuple && length(t.argTypes)==2 && ce_is_protocol(t.argTypes[0],"CeCollectSink")
        var arrayFinalizer=false
        if(enabled) {
            for_each_module_no_order(compiling_program().get_ptr(),$(mod) {
                if(mod.name!="builtin") {
                    for_each_function(mod,"finalize") $(fn) {
                        if(!fn.flags.generated && length(fn.arguments)==1 && fn.arguments[0]._type.baseType==Type.tArray) {arrayFinalizer=true}
                    }
                    for_each_generic(mod,"finalize") $(fn) {if(!fn.flags.generated) {arrayFinalizer=true}}
                }
            })
        }
        return <- new ExprConstBool(at=expr.at,value=enabled && !arrayFinalizer && ce_sink_safe_element(t.argTypes[1].firstType))
    }
}
// Only adjacent binds followed by return: no resource/exception scopes are
// merged, and grouped sources keep their existing snapshot semantics.
def ce_can_collect_fuse(blk:ExprBlock?; start:int; owned:bool) : bool {
    let count=length(blk.list)-start-1
    if(count<1 || !(blk.list[length(blk.list)-1] is ExprReturn)) {return false}
    let ret=blk.list[length(blk.list)-1] as ExprReturn
    if(ret.subexpr==null || ret.returnFlags.returnReference || (owned && !ret.returnFlags.moveSemantics)) {return false}
    if(ret.subexpr is ExprCall && (ret.subexpr as ExprCall).name=="return_from") {return false}
    var consuming=owned
    for(i in range(start,length(blk.list)-1)) {
        let stmt=blk.list[i]
        var binding:ExpressionPtr
        if(stmt is ExprLet) {
            let decl=stmt as ExprLet
            if(length(decl.variables)!=1) {return false}
            binding=clone_expression(decl.variables[0].init)
            consuming=consuming || (decl.variables[0]._type.flags.ref && !decl.variables[0]._type.flags.constant)
        } elif(stmt is ExprCall) {binding=clone_expression(stmt)}
        if(binding==null || !(binding is ExprCall)) {return false}
        let call=binding as ExprCall
        if(call.name!="bind" || length(call.arguments)!=1) {return false}
        if(call.arguments[0] is ExprCall && (call.arguments[0] as ExprCall).name=="and_bind") {return false}
    }
    // Keep consuming scope boundaries (including destruction order). A single
    // consuming map still eliminates every singleton result allocation.
    return consuming ? count==1 : count>=2
}
def ce_collect_emit_scope(blk:ExprBlock?; start:int; builder,sink:string; owned:bool) : ExpressionPtr {
    let stmt=blk.list[start]
    if(stmt is ExprReturn) {
        let ret=stmt as ExprReturn
        if(owned) {return qmacro_block(){ce_collect_emit_move($i(builder),$i(sink),$e(ret.subexpr));return CeUnit()}}
        return qmacro_block(){ce_collect_emit($i(builder),$i(sink),$e(ret.subexpr));return CeUnit()}
    }
    var binding:ExpressionPtr
    if(stmt is ExprLet) {binding=clone_expression((stmt as ExprLet).variables[0].init)} else {binding=clone_expression(stmt)}
    let source=ce_normalize_source(builder,(binding as ExprCall).arguments[0])
    let argument=make_unique_private_name("__ce_sink_item",stmt.at)
    let sourceName=make_unique_private_name("__ce_sink_source",stmt.at)
    let borrow=stmt is ExprLet && (stmt as ExprLet).variables[0]._type.flags.ref && !(stmt as ExprLet).variables[0]._type.flags.constant
    var rest=(ce_collect_emit_scope(blk,start+1,builder,sink,owned) as ExprBlock)
    if(stmt is ExprLet) {
        var declaration=clone_expression(stmt)
        (declaration as ExprLet).variables[0].init=qmacro($i(argument))
        if(owned || borrow) {(declaration as ExprLet).variables[0].init.genFlags.alwaysSafe=true}
        rest.list |> emplace(declaration,0)
    }
    var next=qmacro($($i(argument):typedecl(ce_unwrap($i(builder),$e(source)))) {$e(rest);})
    if(owned) {next=qmacro($(var $i(argument):typedecl(ce_unwrap($i(builder),$e(source)))&) {$e(rest);})}
    elif(borrow) {next=qmacro($(var $i(argument):typedecl(ce_unwrap_borrow($i(builder),$e(source)))&) {$e(rest);})}
    var apply=qmacro($($i(sourceName):typedecl($e(source))) {
        return ce_collect_each($i(builder),$i(sink),$i(sourceName),$e(next))
    })
    if(owned || borrow) {
        apply=qmacro($(var $i(sourceName):typedecl($e(source))) {
            return ce_collect_each_move($i(builder),$i(sink),$i(sourceName),$e(next))
        })
    }
    let execution=ce_source_apply(source,apply,true,false)
    return qmacro_block(){return $e(execution)}
}

// Lower every CE scope independently. Empty scopes end in Zero; only Bind and
// Combine decide whether to enter their continuation. For fallback owns its cursors.
def ce_scope(node : ExpressionPtr; builder : string; collect_mode : bool; var error : string&; owned:bool=false) : ExpressionPtr {
    var source = (qmacro_block() {}) as ExprBlock
    if (node != null) {
        if (node is ExprBlock) {
            source = clone_expression(node) as ExprBlock
        } else {
            source.list |> push <| clone_expression(node)
        }
    }
    if (!empty(source.finalList)) {
        error = "computation: use try_finally(body, cleanup) instead of a native finally on a CE scope"
    }
    var body <- ce_lower(source, 0, builder, collect_mode, error, owned)
    return qmacro_block() { $b(body); }
}

def ce_lower(blk : ExprBlock?; start : int; builder : string; collect_mode : bool;
             var error : string&; owned:bool=false) : array<ExpressionPtr> {
    var output <- ce_lower_impl(blk, start, builder, collect_mode, error, owned)
    if(collect_mode && empty(error) && ce_can_collect_fuse(blk,start,owned)) {
        let sink=make_unique_private_name("__ce_sink",blk.at)
        let emitted=ce_collect_emit_scope(blk,start,builder,sink,owned)
        let fused=qmacro(ce_collect_into($i(builder),$(var $i(sink):typedecl(ce_zero($i(builder)))) {$e(emitted);}))
        let fallback=qmacro(invoke($ {$b(output);}))
        output |> clear()
        output |> push <| qmacro_expr() {
            return <- invoke($ {
                static_if(typeinfo ce_has_collect_sink(ce_collect_sink($i(builder)))) {return <- $e(fused)}
                else {return <- $e(fallback)}
            })
        }
    }

    if (collect_mode) {
        for (stmt in output) {
            if (stmt is ExprReturn) { (stmt as ExprReturn).returnFlags.moveSemantics = true }
        }
    }
    return <- output
}
def ce_lower_impl(blk : ExprBlock?; start : int; builder : string; collect_mode : bool;
             var error : string&; owned:bool=false) : array<ExpressionPtr> {
    var output : array<ExpressionPtr>
    for (index in range(start, length(blk.list))) {
        var stmt = clone_expression(blk.list[index])
        if (stmt is ExprFor) {stmt=ce_normalize_for(builder,stmt)}
        if (collect_mode && (stmt is ExprYield || (stmt is ExprCall && (stmt as ExprCall).name == "yield_from"))) {
            var value : ExpressionPtr
            if (stmt is ExprYield) {
                if ((stmt as ExprYield).returnFlags.moveSemantics) {
                    value=qmacro(ce_return_move($i(builder),$e((stmt as ExprYield).subexpr)))
                } else {value = qmacro(ce_return($i(builder), $e((stmt as ExprYield).subexpr)))}
            } else {
                let call = stmt as ExprCall
                if (length(call.arguments)!=1) {
                    error = "computation: expected expression |> yield_from"
                    return <- output
                }
                value = ce_return_from_source(builder,call.arguments[0],true,owned)
            }
            var rest <- ce_lower(blk, index+1, builder, collect_mode, error, owned)
            let first=make_unique_private_name("__ce_yield_result",stmt.at)
            var append=qmacro($(var $i(first):typedecl($e(value))) {
                return <- ce_combine($i(builder),$i(first),$ { $b(rest); })
            })
            value.at=stmt.at
            var combined=ce_source_apply(value,append,true)
            output |> push <| qmacro_expr() { return $e(combined) }
            return <- output
        }
        if (stmt is ExprReturn) {
            let ret = stmt as ExprReturn
            if (index != length(blk.list)-1 || ret.subexpr == null) {
                error = "computation: return must be the final statement of its scope and have a value"
                return <- output
            }
            if (ret.subexpr is ExprCall && (ret.subexpr as ExprCall).name == "return_from") {
                let call = ret.subexpr as ExprCall
                if (length(call.arguments) != 1) {
                    error = "computation: expected 'return expression |> return_from'"
                    return <- output
                }
                let forwarded=ce_return_from_source(builder,call.arguments[0],collect_mode,owned)
                output |> push <| qmacro_expr() {return $e(forwarded)}
            } elif (owned && ret.returnFlags.moveSemantics) {
                output |> push <| qmacro_expr() {return ce_return_move($i(builder),$e(ret.subexpr))}
            } else {
                if(owned) {
                    var check=qmacro(static_assert(typeinfo can_copy($e(ret.subexpr)),"owned CE: value must be moved; use 'return <- value'"))
                    check.at=stmt.at
                    output |> push <| check
                }
                output |> push <| qmacro_expr() {
                    return ce_return($i(builder), $e(ret.subexpr))
                }
            }
            return <- output
        }
        var binding : ExpressionPtr
        if (stmt is ExprLet) {
            let decl = stmt as ExprLet
            if (length(decl.variables) != 1) {
                error = "computation: declare one variable per statement"
                return <- output
            }
            binding = clone_expression(decl.variables[0].init)
        } elif (stmt is ExprCall) {
            binding = clone_expression(stmt)
        }
        if (binding != null && binding is ExprCall && (binding as ExprCall).name == "bind") {
            let call = binding as ExprCall
            if (length(call.arguments) != 1) {
                error = "computation: expected 'expression |> bind'"
                return <- output
            }
            // Explicit mutable-reference bind can consume move-only inputs even
            // when the collection's output element is copyable.
            let borrow_bind=collect_mode && stmt is ExprLet && (stmt as ExprLet).variables[0]._type.flags.ref && !(stmt as ExprLet).variables[0]._type.flags.constant
            let mutable_bind=owned || borrow_bind
            if (owned && stmt is ExprLet) {
                let variable=(stmt as ExprLet).variables[0]
                if (variable.flags.init_via_move || variable.flags.init_via_clone || variable.flags.inScope) {
                    error="owned CE: bind borrows its payload; use 'var value & = source |> bind'"
                    return <- output
                }
            }
            var rest <- ce_lower(blk, index+1, builder, collect_mode, error, owned)
            if (!empty(error)) { return <- output }
            var source = ce_merge_source(call.arguments[0], builder, error)
            if (!empty(error)) { return <- output }
            let argument = make_unique_private_name("__ce_value", stmt.at)
            if (stmt is ExprLet) {
                var declaration = clone_expression(stmt)
                (declaration as ExprLet).variables[0].init = qmacro($i(argument))
                if (mutable_bind) {(declaration as ExprLet).variables[0].init.genFlags.alwaysSafe=true}
                rest |> emplace(declaration, 0)
            }
            var ordinary = qmacro($($i(argument) : typedecl(ce_unwrap($i(builder), $e(source)))) { $b(rest); })
            if (mutable_bind) {
                ordinary=qmacro($(var $i(argument):typedecl(ce_unwrap($i(builder),$e(source)))&) {$b(rest);})
            }
            if (borrow_bind && !owned) {
                ordinary=qmacro($(var $i(argument):typedecl(ce_unwrap_borrow($i(builder),$e(source)))&) {$b(rest);})
            }
            // Only adjacent bind + final ordinary return. Preserve the original
            // declaration (including its annotation) inside the mapping block.
            var fused = false
            if (!mutable_bind && index+2 == length(blk.list) && blk.list[index+1] is ExprReturn) {
                let ret = blk.list[index+1] as ExprReturn
                if (ret.subexpr != null && !ret.returnFlags.moveSemantics && !ret.returnFlags.returnReference) {
                    fused = !(ret.subexpr is ExprCall && (ret.subexpr as ExprCall).name == "return_from")
                }
            }
            if (fused) {
                rest |> clear()
                if (stmt is ExprLet) {
                    var declaration = clone_expression(stmt)
                    (declaration as ExprLet).variables[0].init = qmacro($i(argument))
                    rest |> push <| declaration
                }
                rest |> push <| clone_expression(blk.list[index+1])
            }
            var continuation = qmacro($($i(argument) : typedecl(ce_unwrap($i(builder), $e(source)))) { $b(rest); })
            var application = ce_bind_application(builder, source, continuation, ordinary, fused, collect_mode)
            {
                let sourceName = make_unique_private_name("__ce_group_source", stmt.at)
                application = ce_bind_application(builder, qmacro($i(sourceName)), continuation, ordinary, fused, collect_mode)
                var next = qmacro($($i(sourceName):typedecl($e(source))) {
                    return $e(application)
                })
                if (collect_mode) {
                    next = qmacro($($i(sourceName):typedecl($e(source))) {
                        return <- $e(application)
                    })
                }
                if (mutable_bind) {((next as ExprMakeBlock)._block as ExprBlock).arguments[0]._type.flags.constant=false}
                var mapper : ExpressionPtr
                if (fused) { mapper = continuation }
                var grouped = ce_merge_apply(call.arguments[0], builder, next, collect_mode, error, mapper, ordinary, mutable_bind)
                output |> push <| qmacro_expr() { return $e(grouped) }
            }
            return <- output
        }
        // A scoped resource is acquired only when this declaration is reached.
        if (binding != null && binding is ExprCall && (binding as ExprCall).name == "use_resource") {
            let call = binding as ExprCall
            if (!(stmt is ExprLet) || length(call.arguments) != 1) {
                error = "computation: expected 'let resource = expression |> use_resource'"
                return <- output
            }
            let variable=(stmt as ExprLet).variables[0]
            let moveResource=variable._type.flags.ref && !variable._type.flags.constant
            if (variable.flags.init_via_move || variable.flags.init_via_clone || variable.flags.inScope) {
                error="use_resource: borrow ownership with 'var resource & = source |> use_resource'"
                return <- output
            }
            var rest <- ce_lower(blk, index+1, builder, collect_mode, error, owned)
            if (!empty(error)) { return <- output }
            let argument = make_unique_private_name("__ce_resource", stmt.at)
            var declaration = clone_expression(stmt)
            (declaration as ExprLet).variables[0].init = qmacro($i(argument))
            if (moveResource) {(declaration as ExprLet).variables[0].init.genFlags.alwaysSafe=true}
            rest |> emplace(declaration, 0)
            var continuation = qmacro($($i(argument) : typedecl($e(call.arguments[0]))) { $b(rest); })
            if (moveResource) {
                continuation=qmacro($(var $i(argument):typedecl($e(call.arguments[0]))) {$b(rest);})
                output |> push <| qmacro_expr() {
                    return ce_using_move($i(builder),$e(call.arguments[0]),$e(continuation),
                        $(var $i(argument):typedecl($e(call.arguments[0]))) {ce_dispose($i(argument))})
                }
                return <- output
            }
            output |> push <| qmacro_expr() {
                return ce_using($i(builder), $e(call.arguments[0]), $e(continuation),
                    $(var $i(argument) : typedecl($e(call.arguments[0])) ) { ce_dispose($i(argument)) })
            }
            return <- output
        }
        var computation : ExpressionPtr
        if (stmt is ExprCall && (stmt as ExprCall).name == "try_with") {
            let call = stmt as ExprCall
            if (!ce_validate_try_with(call, error)) { return <- output }
            var protected_body = ce_scope((call.arguments[0] as ExprMakeBlock)._block, builder, collect_mode, error, owned)
            var handler = clone_expression(call.arguments[1]) as ExprMakeBlock
            var handler_body = handler._block as ExprBlock
            var lowered = ce_scope(handler_body, builder, collect_mode, error, owned) as ExprBlock
            handler_body.list |> clear()
            for (entry in lowered.list) { handler_body.list |> push <| clone_expression(entry) }
            computation = qmacro(ce_try_with($i(builder), $ { $e(protected_body); }, $e(handler)))
        }
        if (stmt is ExprCall && (stmt as ExprCall).name == "try_finally") {
            let call = stmt as ExprCall
            if (length(call.arguments) != 2 || !(call.arguments[0] is ExprMakeBlock)
                    || !(call.arguments[1] is ExprMakeBlock)) {
                error = "computation: try_finally expects two blocks (body, cleanup)"
                return <- output
            }
            let source = (call.arguments[0] as ExprMakeBlock)._block as ExprBlock
            let cleanup_source = (call.arguments[1] as ExprMakeBlock)._block as ExprBlock
            if (!empty(source.arguments) || !empty(cleanup_source.arguments)) {
                error = "computation: try_finally blocks must have no arguments"
                return <- output
            }
            var protected_body = ce_scope(source, builder, collect_mode, error, owned)
            var cleanup = clone_expression(call.arguments[1])
            computation = qmacro(ce_try_finally($i(builder), $ { $e(protected_body); }, $e(cleanup)))
        }
        if (stmt is ExprIfThenElse) {
            var branch = clone_expression(stmt)
            let original = stmt as ExprIfThenElse
            (branch as ExprIfThenElse).if_true = ce_scope(original.if_true, builder, collect_mode, error, owned)
            (branch as ExprIfThenElse).if_false = ce_scope(original.if_false, builder, collect_mode, error, owned)
            computation = qmacro(ce_delay($i(builder), $ { $e(branch); }))
        } elif (stmt is ExprFor || stmt is ExprWhile) {
            var loop = clone_expression(stmt)
            let original_body = stmt is ExprFor ? (stmt as ExprFor).body : (stmt as ExprWhile).body
            var body = ce_scope(original_body, builder, collect_mode, error, owned)
            let step = make_unique_private_name("__ce_iteration", stmt.at)
            let accumulated = make_unique_private_name("__ce_accumulated", stmt.at)
            var checked_body = qmacro_block() {
                let $i(step) = ce_delay($i(builder), $ { $e(body); })
                $i(accumulated) = ce_loop_append($i(builder), $i(accumulated), $i(step))
                if (ce_loop_failed($i(builder), $i(accumulated))) { return $i(accumulated) }
            }
            if (collect_mode) {
                checked_body = qmacro_block() {
                    var inscope $i(step) <- ce_delay($i(builder), $ { $e(body); })
                    ce_collect_append($i(builder), $i(accumulated), $i(step))
                }
            }
            if (owned) {
                checked_body=qmacro_block() {
                    var inscope $i(step) <- ce_delay($i(builder), $ {$e(body);})
                    ce_collect_append($i(builder),$i(accumulated),$i(step))
                    if (ce_loop_failed($i(builder),$i(accumulated))) {return <- $i(accumulated)}
                }
            }
            if (loop is ExprFor) { (loop as ExprFor).body = checked_body }
            else { (loop as ExprWhile).body = checked_body }
            if (stmt is ExprFor) {
                let original=stmt as ExprFor
                var names:array<string>
                for (fallbackIndex in range(length(original.sources))) {
                    names |> push(make_unique_private_name("__ce_fallback_source_{fallbackIndex}",stmt.at))
                }
                var consume=qmacro_block() {
                    let $i(step)=ce_delay($i(builder), $ {$e(body);})
                    $i(accumulated)=ce_loop_append($i(builder),$i(accumulated),$i(step))
                    if (ce_loop_failed($i(builder),$i(accumulated))) {break}
                }
                if (collect_mode) {consume=clone_expression(checked_body)}
                if (owned) {
                    consume=qmacro_block() {
                        var inscope $i(step) <- ce_delay($i(builder), $ {$e(body);})
                        ce_collect_append($i(builder),$i(accumulated),$i(step))
                        if (ce_loop_failed($i(builder),$i(accumulated))) {break}
                    }
                }
                loop=ce_zip_traversal(original,names,null,"",consume)
                loop=ce_zip_source_scopes(original,loop,names,0)
            }
            computation = qmacro(ce_delay($i(builder), $ {
                var $i(accumulated) = ce_zero($i(builder))
                $e(loop)
                return $i(accumulated)
            }))
            if (collect_mode) {
                computation = qmacro(ce_delay($i(builder), $ {
                    var inscope $i(accumulated) <- ce_zero($i(builder))
                    try { $e(loop); } recover {
                        ce_collect_rethrow($i(builder), $i(accumulated))
                    }
                    return <- $i(accumulated)
                }))
            }
            if (stmt is ExprWhile) {
                let condition=(stmt as ExprWhile).cond
                var custom=qmacro(ce_while($i(builder), $ { return $e(condition) },
                    $ { return ce_delay($i(builder), $ { $e(body); }) }))
                if (collect_mode) {
                    custom=qmacro(ce_while($i(builder), $ { return $e(condition) },
                        $ { return <- ce_delay($i(builder), $ { $e(body); }) }))
                }
                computation=ce_loop_dispatch(custom,computation,collect_mode)
            } else {
                let original=stmt as ExprFor
                if (length(original.sources)>1) {
                    // Preserve native zip ordering with explicitly owned cursors so
                    // producer and consumer panics cannot strand hidden iterators.
                    let visitor=make_unique_private_name("__ce_zip_visit",stmt.at)
                    var iteration=qmacro($ { return ce_delay($i(builder), $ { $e(body); }) })
                    if (collect_mode) {
                        iteration=qmacro($ { return <- ce_delay($i(builder), $ { $e(body); }) })
                    }
                    let arity=length(original.sources)
                    var sourceNames:array<string>
                    for (sourceIndex in range(arity)) {
                        let sourceName=make_unique_private_name("__ce_zip_source_{sourceIndex}",stmt.at)
                        sourceNames |> push(sourceName)
                    }
                    var traversal=ce_zip_traversal(original,sourceNames,iteration,visitor,null)
                    traversal=ce_zip_source_scopes(original,traversal,sourceNames,0)
                    var driver=qmacro($($i(visitor):block<(body:block<():typedecl(ce_zero($i(builder)))>):bool>) {
                        $e(traversal)
                    })
                    var custom=qmacro(ce_for_zip($i(builder),$v(arity),$e(driver)))
                    computation=ce_loop_dispatch(custom,computation,collect_mode)
                } elif (length(original.sources)==1 && length(original.iterators)==1) {
                    let source=original.sources[0]
                    let item=string(original.iterators[0])
                    var callback=qmacro($($i(item):typedecl(ce_for_element($e(source)))) {
                        return ce_delay($i(builder), $ { $e(body); })
                    })
                    var mutableCallback=qmacro($(var $i(item):typedecl(ce_for_element($e(source)))&) {
                        return ce_delay($i(builder), $ { $e(body); })
                    })
                    if (collect_mode) {
                        callback=qmacro($($i(item):typedecl(ce_for_element($e(source)))) {
                            return <- ce_delay($i(builder), $ { $e(body); })
                        })
                        mutableCallback=qmacro($(var $i(item):typedecl(ce_for_element($e(source)))&) {
                            return <- ce_delay($i(builder), $ { $e(body); })
                        })
                    }
                    var mutableCall=ce_for_application(builder,source,mutableCallback,computation,collect_mode,true,stmt.at)
                    var ordinaryCall=ce_for_application(builder,source,callback,computation,collect_mode,false,stmt.at)
                    if (collect_mode) {
                        computation=qmacro(invoke($ {
                            static_if ((((typeinfo is_array($e(source))) || (typeinfo is_dim($e(source)))) && !(typeinfo is_const($e(source)))) || (typeinfo ce_for_ref_iterator($e(source)))) {
                                return <- $e(mutableCall)
                            } else { return <- $e(ordinaryCall) }
                        }))
                    } else {
                        computation=qmacro(invoke($ {
                            static_if ((((typeinfo is_array($e(source))) || (typeinfo is_dim($e(source)))) && !(typeinfo is_const($e(source)))) || (typeinfo ce_for_ref_iterator($e(source)))) {
                                return $e(mutableCall)
                            } else { return $e(ordinaryCall) }
                        }))
                    }
                }
            }
        } elif (stmt is ExprBlock) {
            var scope = ce_scope(stmt, builder, collect_mode, error, owned)
            computation = qmacro(ce_delay($i(builder), $ { $e(scope); }))
        }
        if (computation != null) {
            if (!empty(error)) { return <- output }
            if (index == length(blk.list)-1) {
                output |> push <| qmacro_expr() { return $e(computation) }
            } else {
                var rest <- ce_lower(blk, index+1, builder, collect_mode, error, owned)
                var combined=qmacro(ce_combine($i(builder), $e(computation), $ { $b(rest); }))
                if (collect_mode) {
                    let first=make_unique_private_name("__ce_scope_result",stmt.at)
                    var append=qmacro($(var $i(first):typedecl($e(computation))) {
                        return <- ce_combine($i(builder),$i(first),$ { $b(rest); })
                    })
                    computation.at=stmt.at
                    combined=ce_source_apply(computation,append,true)
                }
                output |> push <| qmacro_expr() { return $e(combined) }
            }
            return <- output
        }
        if (!(stmt is ExprLet) && !(stmt is ExprCall) && !(stmt is ExprCallMacro)
                && !(stmt is ExprCopy) && !(stmt is ExprMove)
                && !(stmt is ExprOp1) && !(stmt is ExprOp2) && !(stmt is ExprAssert)) {
            error = "computation: unsupported statement {stmt.__rtti}"
            return <- output
        }
        output |> push <| clone_expression(stmt)
    }
    output |> push <| qmacro_expr() { return ce_zero($i(builder)) }
    return <- output
}

// Run is applied only to the outer outcome, after Delay and resource cleanup.
[typeinfo_macro(name="ce_has_run")]
class CeHasRun : AstTypeInfoMacro {
    def override getAstChange(expr:ExprTypeInfo?; var errors:das_string) : ExpressionPtr {
        if (expr.subexpr==null || expr.subexpr._type==null) { errors := "computation: ce_run result type must be inferred"; return null }
        let t=expr.subexpr._type
        if (t.baseType==Type.tVoid) { errors := "computation: ce_run must return a value, not void"; return null }
        return <- new ExprConstBool(at=expr.at,value=!ce_is_protocol(t,"CeRunFallback"))
    }
}

def ce_run_scope(builder:string; outcome:ExpressionPtr; owned:bool; at:LineInfo) : ExpressionPtr {
    let input=make_unique_private_name("__ce_run_outcome",at)
    var supported=qmacro(typeinfo ce_has_run(ce_run($i(builder),$i(input))))
    supported.at=at
    var finish=qmacro_block() {
        static_if ($e(supported)) {
            static_if (typeinfo can_copy(ce_run($i(builder),$i(input)))) {
                return ce_run($i(builder),$i(input))
            } else { return <- ce_run($i(builder),$i(input)) }
        } else { return $i(input) }
    }
    if (owned) {
        let result=make_unique_private_name("__ce_run_result",at)
        return qmacro_block() {
            var inscope $i(input) <- $e(outcome)
            static_if ($e(supported)) {
                static_if (typeinfo can_copy(ce_run($i(builder),$i(input)))) {
                    var $i(result)=default<typedecl(ce_run($i(builder),$i(input)))>
                    try { $i(result)=ce_run($i(builder),$i(input)) } recover { ce_owned_source_rethrow($i(input)) }
                    return $i(result)
                } else {
                    var inscope $i(result):typedecl(ce_run($i(builder),$i(input)))
                    try { $i(result) <- ce_run($i(builder),$i(input)) } recover { ce_owned_source_rethrow($i(input)) }
                    return <- $i(result)
                }
            } else { return <- $i(input) }
        }
    }
    return qmacro_block() { var $i(input)=$e(outcome); $e(finish); }
}

[call_macro(name="computation")]
class ComputationMacro : AstCallMacro {
    serial : int = 0
    def override canVisitArgument(expr : ExprCallMacro?; index : int) : bool {
        return index == 0 || (index == 1 && expr.name=="__ce_lower_protocol")
    }
    def override canFoldReturnResult(expr : ExprCallMacro?) : bool { return false }
    def override visit(prog : ProgramPtr; mod : Module?; var expr : ExprCallMacro?) : ExpressionPtr {
        if (length(expr.arguments)==2 && expr.name=="computation" && expr.arguments[1] is ExprMakeBlock) {
            // A saved local may still be auto on the first inference pass.
            // Do not freeze default<auto> into the protocol probe.
            if (expr.arguments[0]._type==null || expr.arguments[0]._type.isAutoOrAlias) {return null}
            // Keep the same macro object for a second inference pass. The descriptor
            // call is inferred with a type-only default and removed before execution.
            // The original builder expression survives only in the final invoke.
            var builder_type=clone_type(expr.arguments[0]._type)
            builder_type.flags.ref=false
            builder_type.flags.constant=false
            var expanded=clone_expression(expr) as ExprCallMacro
            expanded.name := "__ce_lower_protocol"
            var body=clone_expression(expr.arguments[1])
            expanded.arguments[1]=qmacro(ce_protocol(default<$t(builder_type)>))
            expanded.arguments |> push <| body
            return expanded
        }
        if (length(expr.arguments) != 3 || expr.name!="__ce_lower_protocol" || !(expr.arguments[2] is ExprMakeBlock)) {
            macro_error(prog, expr.at, "computation expects a builder and a trailing block")
            return null
        }
        let blk = (expr.arguments[2] as ExprMakeBlock)._block as ExprBlock
        if (!empty(blk.arguments) || !empty(blk.finalList)) {
            macro_error(prog, expr.at, "computation: block arguments are unsupported; use try_finally(body, cleanup) for cleanup")
            return null
        }
        if (expr.arguments[0]._type == null) { return null }
        serial++
        let name = make_unique_private_name("__ce_builder_{serial}", expr.at)
        let protocol = expr.arguments[1]._type
        if (protocol == null) { return null }
        let bt = expr.arguments[0]._type
        if (ce_is_protocol(protocol,"CeMissingProtocol")) {
            macro_error(prog,expr.at,"computation: missing ce_protocol for builder {describe(bt)}; define ce_protocol(builder) returning CeValueProtocol, CeCollectProtocol, ce_sequence_protocol(type<T>) or ce_resumable_protocol(type<Event>)")
            return null
        }
        let resumable_mode = protocol.baseType==Type.tTuple && length(protocol.argTypes)==2 && ce_is_protocol(protocol.argTypes[0],"CeResumableProtocol")
        let sequence_mode = ce_is_sequence_protocol(protocol) || resumable_mode
        if (sequence_mode) {
            var error : string
            var raw=clone_expression(blk)
            if(resumable_mode) {
                raw=ce_resumable_scope(raw,name,error,$(source:ExpressionPtr) {
                    if(source is ExprCall && (source as ExprCall).name=="and_bind") {
                        let merged=ce_resumable_merge_source(source,name,error)
                        if(!empty(error)) {return null}
                        return qmacro(ce_await_source($i(name),$e(merged)))
                    }
                    return qmacro(ce_await_source($i(name),$e(source)))
                })
            }
            if(!empty(error)) {macro_error(prog,expr.at,error);return null}
            var body = ce_sequence_scope(raw, 0, protocol.argTypes[1], ce_sequence_has_resources(raw), error, name)
            if (!empty(error)) {
                macro_error(prog, expr.at, error)
                return null
            }
            var element = clone_type(protocol.argTypes[1])
            var builder_type = clone_type(bt)
            var run=ce_run_scope(name,qmacro(ce_sequence_run($i(name), source)),true,expr.at)
            return qmacro(invoke($($i(name) : $t(builder_type)) {
                var source <- generator<$t(element)> {
                    $e(body)
                    return false
                }
                $e(run);
            }, $e(expr.arguments[0])))
        }
        let owned=ce_is_protocol(protocol,"CeOwnedProtocol")
        let collect_mode = ce_is_protocol(protocol, "CeCollectProtocol") || owned
        if (!collect_mode && !ce_is_protocol(protocol, "CeValueProtocol")) {
            macro_error(prog, expr.at, "computation: ce_protocol must return a builder_protocol descriptor; builder {describe(bt)} returned {describe(protocol)}; expected CeValueProtocol, CeCollectProtocol, CeOwnedProtocol, ce_sequence_protocol(type<T>) or ce_resumable_protocol(type<Event>)")
            return null
        }
        var error : string
        var body <- ce_lower(blk, 0, name, collect_mode, error, owned)
        if (!empty(error)) {
            macro_error(prog, expr.at, error)
            return null
        }
        var builder_type = clone_type(expr.arguments[0]._type)
        let input = make_unique_private_name("__ce_input_{serial}", expr.at)
        var run=ce_run_scope(name,qmacro(ce_delay($i(name), $ { $b(body); })),collect_mode,expr.at)
        var scope = qmacro($($i(input) : $t(builder_type)) {
            var $i(name) = $i(input)
            $e(run);
        })
        var result = qmacro(invoke($e(scope), $e(expr.arguments[0])))
        result.at = expr.at
        return result
    }
}














// Sequence bodies lower directly into a native generator: no eager array and
// no escaping stack continuations. Bind becomes a nested loop over the tail.
// Protect only iterator sources; native array/range ownership stays in the generator.
[typeinfo_macro(name="ce_sequence_source")]
class CeSequenceSource : AstTypeInfoMacro {
    def override getAstChange(expr:ExprTypeInfo?; var errors:das_string) : ExpressionPtr {
        if (expr.subexpr==null || expr.subexpr._type==null) {
            errors := "sequence: source type must be inferred"
            return null
        }
        let source=expr.subexpr
        if (source._type.baseType==Type.tIterator) {
            return qmacro(invoke($ {
                static_if (typeinfo is_ref_value(type<$t(source._type.firstType)>)) {
                    return <- ce_sequence_input($e(source))
                } static_elif (typeinfo can_copy(type<$t(source._type.firstType)>)) {
                    return <- ce_sequence_input($e(source))
                } else {return <- ce_sequence_own_elements($e(source))}
            }))
        }
        return clone_expression(source)
    }
}
def ce_sequence_protect_loop(loop:ExpressionPtr) : ExpressionPtr {
    var result=clone_expression(loop) as ExprFor
    for (source in result.sources) {source=qmacro(typeinfo ce_sequence_source($e(source)))}
    return result
}

def ce_sequence_scope(node : ExpressionPtr; start : int; element : TypeDeclPtr; share : bool; var error : string&; builder:string) : ExpressionPtr {
    var blk = (qmacro_block() {}) as ExprBlock
    if (node == null) { return blk }
    if (node is ExprBlock) { blk = clone_expression(node) as ExprBlock }
    else { blk.list |> push <| clone_expression(node) }
    if (!empty(blk.finalList)) {
        error = "sequence: native finally is unsupported; keep resource ownership outside the iterator"
    }
    var output : array<ExpressionPtr>
    for (index in range(start, length(blk.list))) {
        var stmt = clone_expression(blk.list[index])
        if (stmt is ExprFor) {stmt=ce_normalize_for(builder,stmt)}
        var binding : ExpressionPtr
        if (share && stmt is ExprLet && length((stmt as ExprLet).variables)>1) {
            var expanded : array<ExpressionPtr>
            for (i in range(length((stmt as ExprLet).variables))) {
                var declaration = clone_expression(stmt) as ExprLet
                var variable = declaration.variables[i]
                declaration.variables.resize(1)
                declaration.variables[0] = variable
                expanded |> push <| declaration
            }
            for (i in range(index+1, length(blk.list))) { expanded |> push <| clone_expression(blk.list[i]) }
            var scope = qmacro_block() { $b(expanded); }
            var lowered = ce_sequence_scope(scope, 0, element, share, error, builder)
            for (entry in (lowered as ExprBlock).list) { output |> push <| clone_expression(entry) }
            return qmacro_block() { $b(output); }
        }
        if (stmt is ExprLet && length((stmt as ExprLet).variables)==1) {
            binding = (stmt as ExprLet).variables[0].init
        } elif (stmt is ExprCall) { binding = clone_expression(stmt) }
        if (share && stmt is ExprLet && length((stmt as ExprLet).variables)==1) {
            let variable = (stmt as ExprLet).variables[0]
            let marker = (binding != null && binding is ExprCall
                && ((binding as ExprCall).name=="bind" || (binding as ExprCall).name=="use_resource"))
            if (!variable._type.flags.constant && !marker) {
                if (variable._type.flags.ref || variable.flags.inScope || (stmt as ExprLet).letFlags.inScope
                        || variable.flags.init_via_move || variable.flags.init_via_clone) {
                    error = "sequence: shared locals require copyable values, without explicit reference, inscope, move or clone"
                    return blk
                }
                let cell = make_unique_private_name("__seq_cell_{variable.name}", stmt.at)
                let original_name = "{variable.name}"
                let initial_name = make_unique_private_name("__seq_initial_{variable.name}", stmt.at)
                var declaration = clone_expression(stmt)
                (declaration as ExprLet).variables[0].name := initial_name
                var initialization = qmacro(invoke($ {
                    $e(declaration)
                    return $i(initial_name)
                }))
                var tail : array<ExpressionPtr>
                var cell_declaration = qmacro_expr() {
                    let $i(cell) = ce_sequence_new_cell($e(initialization)) |> use_resource
                }
                cell_declaration.at = stmt.at
                // Native generator loop labels use source coordinates. Keep
                // the synthetic cell loop distinct from its enclosing bind.
                cell_declaration.at.column += 1
                for (i in range(index+1, length(blk.list))) { tail |> push <| clone_expression(blk.list[i]) }
                var scope = qmacro_block() { $b(tail); }
                scope = ce_sequence_replace_local(scope, original_name, cell)
                var complete : array<ExpressionPtr>
                complete |> push <| cell_declaration
                for (entry in (scope as ExprBlock).list) { complete |> push <| clone_expression(entry) }
                scope = qmacro_block() { $b(complete); }
                var lowered = ce_sequence_scope(scope, 0, element, share, error, builder)
                for (entry in (lowered as ExprBlock).list) { output |> push <| clone_expression(entry) }
                return qmacro_block() { $b(output); }
            }
        }
        if (binding != null && binding is ExprCall) {
            let call = binding as ExprCall
            if (call.name == "use_resource") {
                if (!(stmt is ExprLet) || length(call.arguments)!=1) {
                    error = "sequence: expected 'let resource = expression |> use_resource'"
                    return blk
                }
                let identity = "{(stmt as ExprLet).variables[0].name}"
                let owned = make_unique_private_name("__seq_owned_{identity}", stmt.at)
                let variable=(stmt as ExprLet).variables[0]
                if (variable.flags.init_via_move || variable.flags.init_via_clone || variable.flags.inScope) {
                    error="use_resource: borrow ownership with 'var resource & = source |> use_resource'"
                    return blk
                }
                if (variable._type.flags.ref && !variable._type.flags.constant) {
                    let cell=make_unique_private_name("__seq_resource_cell_{identity}",stmt.at)
                    var raw_tail=qmacro_block() {} as ExprBlock
                    for(i in range(index+1,length(blk.list))) {raw_tail.list |> push <| clone_expression(blk.list[i])}
                    let replaced=ce_sequence_replace_local(raw_tail,identity,cell)
                    var body=ce_sequence_scope(replaced,0,element,share,error,builder)
                    var decl=clone_expression(stmt)
                    (decl as ExprLet).variables[0].init=qmacro($i(cell).value)
                    (decl as ExprLet).variables[0].init.genFlags.alwaysSafe=true
                    (body as ExprBlock).list |> emplace(decl,0)
                    var setup <- qmacro_block_to_array() {var $i(cell)=ce_resource_cell_move($e(call.arguments[0]));}
                    var cleanup=qmacro($ {ce_resource_cell_close($i(cell),$(var $i(owned):typedecl($i(cell).value)) {ce_dispose($i(owned))})})
                    output |> push <| ce_sequence_guard(body,setup,cleanup,element,stmt.at,identity)
                    return qmacro_block() {$b(output);}
                }
                var rest = ce_sequence_scope(blk, index+1, element, share, error, builder)
                var decl = clone_expression(stmt)
                (decl as ExprLet).variables[0].init = qmacro($i(owned))
                var tail : array<ExpressionPtr>
                tail |> push <| decl
                for (entry in (rest as ExprBlock).list) { tail |> push <| clone_expression(entry) }
                rest = qmacro_block() { $b(tail); }
                var setup <- qmacro_block_to_array() { var $i(owned) = $e(call.arguments[0]); }
                var cleanup = qmacro($ { ce_dispose($i(owned)) })
                output |> push <| ce_sequence_guard(rest, setup, cleanup, element, stmt.at, identity)
                return qmacro_block() { $b(output); }
            }
            if (call.name == "try_finally") {
                if (!(stmt is ExprCall) || length(call.arguments)!=2
                        || !(call.arguments[0] is ExprMakeBlock) || !(call.arguments[1] is ExprMakeBlock)) {
                    error = "sequence: try_finally expects two blocks (body, cleanup)"
                    return blk
                }
                let body = (call.arguments[0] as ExprMakeBlock)._block as ExprBlock
                let cleanup = (call.arguments[1] as ExprMakeBlock)._block as ExprBlock
                if (!empty(body.arguments) || !empty(cleanup.arguments)) {
                    error = "sequence: try_finally blocks must have no arguments"
                    return blk
                }
                var lowered = ce_sequence_scope(body, 0, element, share, error, builder)
                var setup : array<ExpressionPtr>
                output |> push <| ce_sequence_guard(lowered, setup, call.arguments[1], element, stmt.at, "finally")
                continue
            }
            if (call.name == "try_with") {
                if (!ce_validate_try_with(call, error)) { return blk }
                var body = ce_sequence_scope((call.arguments[0] as ExprMakeBlock)._block, 0, element, share, error, builder)
                var handler = clone_expression(call.arguments[1]) as ExprMakeBlock
                var handler_body = handler._block as ExprBlock
                var fallback = ce_sequence_scope(handler_body, 0, element, share, error, builder)
                var generated = qmacro_expr() {
                    return <- generator<$t(element)> { $e(fallback); return false }
                }
                handler_body.list |> clear()
                handler_body.list |> push <| generated
                handler.mmFlags.isLambda = true
                handler_body.blockFlags.isLambdaBlock = true
                let item = make_unique_private_name("__seq_recovered", stmt.at)
                let input = make_unique_private_name("__seq_try_source", stmt.at)
                let recovery = make_unique_private_name("__seq_try_handler", stmt.at)
                var source = qmacro(invoke($ {
                    var $i(input) <- generator<$t(element)> { $e(body); return false }
                    var $i(recovery) <- $e(handler)
                    return <- ce_sequence_recover($i(input), $i(recovery))
                }))
                var loop = qmacro_expr() { for ($i(item) in $e(source)) {} }
                (loop as ExprFor).body = qmacro_block() {
                    static_if (typeinfo can_copy(type<$t(element)>)) {yield $i(item)}
                    else {yield <- $i(item)}
                }
                loop.at=stmt.at
                (loop as ExprFor).body.at=stmt.at
                output |> push <| ce_sequence_protect_loop(loop)
                continue
            }
            if (call.name == "bind") {
                if (length(call.arguments)!=1) {
                    error = "sequence: expected expression |> bind"
                    return blk
                }
                let name = make_unique_private_name("__seq_item", stmt.at)
                var declarations : array<ExpressionPtr>
                if (stmt is ExprLet) {
                    var decl = clone_expression(stmt)
                    (decl as ExprLet).variables[0].init = qmacro($i(name))
                    declarations |> push <| decl
                }
                for (i in range(index+1, length(blk.list))) { declarations |> push <| clone_expression(blk.list[i]) }
                var raw_tail = qmacro_block() { $b(declarations); }
                var rest = ce_sequence_scope(raw_tail, 0, element, share, error, builder)
                let normalized=ce_normalize_source(builder,call.arguments[0])
                var loop = qmacro_expr() { for ($i(name) in $e(normalized)) {} }
                (loop as ExprFor).body = rest
                loop.at = stmt.at
                (loop as ExprFor).body.at = stmt.at
                output |> push <| ce_sequence_protect_loop(loop)
                return qmacro_block() { $b(output); }
            }
        }
        if (stmt is ExprReturn) {
            error = "sequence: use yield or expression |> yield_from, not return"
            return blk
        } elif (stmt is ExprCall && (stmt as ExprCall).name == "yield_value") {
            let call = stmt as ExprCall
            if (length(call.arguments)!=1) { error = "sequence: expected expression |> yield_value"; return blk }
            output |> push <| qmacro_expr() { yield $e(call.arguments[0]) }
        } elif (stmt is ExprCall && (stmt as ExprCall).name == "yield_from") {
            let call = stmt as ExprCall
            if (length(call.arguments)!=1) {
                error = "sequence: expected expression |> yield_from"
                return blk
            }
            let name = make_unique_private_name("__seq_yield", stmt.at)
            let normalized=ce_normalize_source(builder,call.arguments[0])
            var loop = qmacro_expr() {
                for ($i(name) in $e(normalized)) {
                    static_if (typeinfo can_copy(type<$t(element)>)) {yield $i(name)}
                    else {yield <- $i(name)}
                }
            }
            loop.at = stmt.at
            (loop as ExprFor).body.at = stmt.at
            output |> push <| ce_sequence_protect_loop(loop)
        } elif (stmt is ExprIfThenElse) {
            var branch = clone_expression(stmt) as ExprIfThenElse
            branch.if_true = ce_sequence_scope(branch.if_true, 0, element, share, error, builder)
            branch.if_false = ce_sequence_scope(branch.if_false, 0, element, share, error, builder)
            output |> push <| branch
        } elif (stmt is ExprFor) {
            var loop = clone_expression(stmt) as ExprFor
            loop.body = ce_sequence_scope(loop.body, 0, element, share, error, builder)
            output |> push <| ce_sequence_protect_loop(loop)
        } elif (stmt is ExprWhile) {
            var loop = clone_expression(stmt) as ExprWhile
            loop.body = ce_sequence_scope(loop.body, 0, element, share, error, builder)
            output |> push <| loop
        } elif (stmt is ExprBlock) {
            output |> push <| ce_sequence_scope(stmt, 0, element, share, error, builder)
        } elif (stmt is ExprYield || stmt is ExprLet || stmt is ExprCall
                || stmt is ExprCallMacro || stmt is ExprCopy || stmt is ExprMove
                || stmt is ExprOp1 || stmt is ExprOp2 || stmt is ExprAssert) {
            output |> push <| clone_expression(stmt)
        } else {
            error = "sequence: unsupported statement {stmt.__rtti}"
            return blk
        }
    }
    return qmacro_block() { $b(output); }
}



// Body and finalizer are owned by one scope iterator; its child is closed first.
def ce_sequence_guard(body : ExpressionPtr; var setup : array<ExpressionPtr>;
                      cleanup : ExpressionPtr; element : TypeDeclPtr; at : LineInfo; identity : string) : ExpressionPtr {
    let item = make_unique_private_name("__seq_scoped_{identity}", at)
    let child = make_unique_private_name("__seq_child_{identity}", at)
    let finish = make_unique_private_name("__seq_finish_{identity}", at)
    var cleanup_lambda = clone_expression(cleanup) as ExprMakeBlock
    cleanup_lambda.mmFlags.isLambda = true
    (cleanup_lambda._block as ExprBlock).blockFlags.isLambdaBlock = true
    var factory_expr = qmacro($ {
        var $i(child) <- generator<$t(element)> { $e(body); return false }
        var $i(finish) <- $e(cleanup_lambda)
        return <- ce_sequence_scoped($i(child), $i(finish))
    })
    var factory = (factory_expr as ExprMakeBlock)._block as ExprBlock
    var entries : array<ExpressionPtr>
    for (entry in setup) { entries |> push <| clone_expression(entry) }
    for (entry in factory.list) { entries |> push <| clone_expression(entry) }
    factory.list |> clear()
    for (entry in entries) { factory.list |> push <| clone_expression(entry) }
    var source = qmacro(invoke($e(factory_expr)))
    var loop = qmacro_expr() { for ($i(item) in $e(source)) {} }
    (loop as ExprFor).body = qmacro_block() {
                    static_if (typeinfo can_copy(type<$t(element)>)) {yield $i(item)}
                    else {yield <- $i(item)}
                }
    loop.at = at
    (loop as ExprFor).body.at = at
    return ce_sequence_protect_loop(loop)
}




[macro_interface]
class SequenceResourceFinder : AstVisitor {
    found : bool = false
    def override preVisitExprCall(expr : ExprCall?) {
        if (expr.name=="use_resource" || expr.name=="try_finally" || expr.name=="try_with") { found=true }
    }
}
def ce_sequence_has_resources(body : ExpressionPtr) : bool {
    var finder = new SequenceResourceFinder()
    make_visitor(*finder) $(adapter) { visit(body, adapter) }
    let result = finder.found
    unsafe { delete finder }
    return result
}




// Substitute only references to this declaration. Nested locals, block
// arguments and for iterators with the same name retain their own bindings.
[macro_interface]
class SequenceLocalReferences : AstVisitor {
    original : string
    cell : string
    hidden : bool = false
    scopes : array<bool>
    def save() { scopes |> push(hidden) }
    def restore() { hidden=scopes[length(scopes)-1]; scopes |> pop() }
    def override preVisitExprBlock(blk : ExprBlock?) {
        self.save()
        for (arg in blk.arguments) { if (arg.name==original) {hidden=true} }
    }
    def override visitExprBlock(var blk : ExprBlock?) : ExpressionPtr { self.restore(); return blk }
    def override visitExprLetVariable(expr : ExprLet?; var arg : VariablePtr; lastArg : bool) : VariablePtr {
        if (arg.name==original) {hidden=true}
        return arg
    }
    def override preVisitExprFor(expr : ExprFor?) { self.save() }
    def override preVisitExprForStack(expr : ExprFor?) {
        for (name in expr.iterators) { if (name==original) {hidden=true} }
    }
    def override visitExprFor(var expr : ExprFor?) : ExpressionPtr { self.restore(); return expr }
    def override visitExprVar(var expr : ExprVar?) : ExpressionPtr {
        if (!hidden && expr.name==original) {
            var result = qmacro($i(cell).value)
            result.at=expr.at
            return result
        }
        return expr
    }
}
def ce_sequence_replace_local(body : ExpressionPtr; original, cell : string) : ExpressionPtr {
    var visitor = new SequenceLocalReferences(original=original,cell=cell)
    var result : ExpressionPtr
    make_visitor(*visitor) $(adapter) { result=visit(body,adapter) }
    unsafe {delete visitor}
    return result
}





def ce_validate_try_with(call : ExprCall?; var error : string&) : bool {
    if (length(call.arguments)!=2 || !(call.arguments[0] is ExprMakeBlock)
            || !(call.arguments[1] is ExprMakeBlock)) {
        error="computation: try_with expects a body block and a handler block"
        return false
    }
    let body=(call.arguments[0] as ExprMakeBlock)._block as ExprBlock
    let handler=(call.arguments[1] as ExprMakeBlock)._block as ExprBlock
    if (!empty(body.arguments) || length(handler.arguments)!=1) {
        error="computation: try_with body takes no arguments; handler takes one string message"
        return false
    }
    return true
}


// Only descriptors are recognized here, never concrete builder types/modules.
def ce_is_protocol(t : TypeDeclPtr; name : string) : bool {
    return (t != null && t.baseType==Type.tStructure && t.structType.name==name
        && t.structType._module.name=="builder_protocol")
}
def ce_is_sequence_protocol(t : TypeDeclPtr) : bool {
    return (t != null && t.baseType==Type.tTuple && length(t.argTypes)==2
        && ce_is_protocol(t.argTypes[0], "CeSequenceProtocol"))
}














