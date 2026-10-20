options gen2
module derive_optics public
require ./derive_optics_runtime.das public
require daslib/macro_boost
require daslib/ast_boost
require daslib/templates_boost
require strings

// Only immutable compile-time paths are accepted. No runtime reflection/string lookup.
def private optics_constant(e:ExpressionPtr;depth:int=0) : tuple<ok:bool;value:string> {
    if(e==null || depth>32) {return (ok=false,value="")}
    if(e is ExprConstString) {return (ok=true,value=string((e as ExprConstString).value))}
    if(e is ExprRef2Value) {return optics_constant((e as ExprRef2Value).subexpr,depth+1)}
    if(e is ExprVar) {
        let variable=(e as ExprVar).variable
        if(variable!=null && variable._type!=null && variable._type.flags.constant) {return optics_constant(variable.init,depth+1)}
    }
    return (ok=false,value="")
}
def private optics_parts(path:string;var error:string&) : array<string> {
    var result:array<string>
    if(length(path)==0) {error="optic: path must not be empty";return <- result}
    var part=""
    for(c in path) {
        if(c==46) {
            if(length(part)==0) {error="optic: empty path component";return <- result}
            result |> push(part);part=""
        } else {
            if(!((c>=65 && c<=90) || (c>=97 && c<=122) || c==95 || (length(part)>0 && c>=48 && c<=57))) {
                error="optic: only struct field names separated by dots are supported; match Option/variant explicitly and modify collections as a whole"
                return <- result
            }
            part+=to_char(c)
        }
    }
    if(length(part)==0) {error="optic: empty path component";return <- result}
    result |> push(part)
    return <- result
}
def private optics_focus(root:TypeDeclPtr;parts:array<string>;prog:ProgramPtr;at:LineInfo) : TypeDeclPtr {
    var td=clone_type(root)
    for(name in parts) {
        macro_verify(td.baseType==Type.tStructure,prog,at,"optic: cannot traverse '{name}' in {describe(td)}; only plain struct fields form a total path")
        macro_verify(!td.structType.flags.isClass && td.structType.parent==null,prog,at,"optic: classes/inheritance require a custom optic")
        var found=false
        for(field in td.structType.fields) {
            if(field.name==name) {td=clone_type(field._type);found=true;break}
        }
        macro_verify(found,prog,at,"optic: field '{name}' was not found in the selected struct")
    }
    td.flags.constant=false;td.flags.ref=false
    return td
}
def private optics_access(root:ExpressionPtr;parts:array<string>) : ExpressionPtr {
    var access=clone_expression(root)
    for(name in parts) {access=qmacro($e(access).$f(name))}
    return access
}
// A field/index projected from an owning temporary loses the outer owner.
// Require passing that owner with its complete path instead.
def private optics_temporary_projection(e:ExpressionPtr) : bool {
    if(e==null) {return false}
    var parent:ExpressionPtr
    if(e is ExprField) {parent=(e as ExprField).value}
    elif(e is ExprAsVariant) {parent=(e as ExprAsVariant).value}
    elif(e is ExprAt) {parent=(e as ExprAt).subexpr}
    elif(e is ExprRef2Value) {return optics_temporary_projection((e as ExprRef2Value).subexpr)}
    if(parent==null) {return false}
    if(parent._type!=null && !parent._type.flags.ref && !parent._type.canCopy) {return true}
    return optics_temporary_projection(parent)
}

[call_macro(name="optic")]
class OpticPath : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {
        macro_verify(length(expr.arguments)==1,prog,expr.at,"optic expects one constant field path")
        let path=optics_constant(expr.arguments[0])
        if(!path.ok && expr.arguments[0]._type==null) {return null}
        macro_verify(path.ok,prog,expr.at,"optic: path must be a literal or immutable constant string")
        var problem=""
        var inscope parts <- optics_parts(path.value,problem)
        macro_verify(problem=="",prog,expr.at,problem)
        return qmacro($v(path.value))
    }
}
[call_macro(name="optic_then")]
class OpticThen : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {
        macro_verify(length(expr.arguments)==2,prog,expr.at,"optic_then expects two constant field paths")
        let left=optics_constant(expr.arguments[0]);let right=optics_constant(expr.arguments[1])
        if((!left.ok && expr.arguments[0]._type==null) || (!right.ok && expr.arguments[1]._type==null)) {return null}
        macro_verify(left.ok && right.ok,prog,expr.at,"optic_then: paths must be literal or immutable constant strings")
        var problem=""
        var inscope lp <- optics_parts(left.value,problem)
        macro_verify(problem=="",prog,expr.at,problem)
        var inscope rp <- optics_parts(right.value,problem)
        macro_verify(problem=="",prog,expr.at,problem)
        let path=left.value+"."+right.value
        return qmacro($v(path))
    }
}
[call_macro(name="optic_get")]
class OpticGet : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {
        macro_verify(length(expr.arguments)==2,prog,expr.at,"optic_get expects source and constant path")
        if(expr.arguments[0]._type==null) {return null}
        macro_verify(!optics_temporary_projection(expr.arguments[0]),prog,expr.at,"optic: bind the temporary owner to a variable or pass it with the complete field path")
        let path=optics_constant(expr.arguments[1])
        if(!path.ok && expr.arguments[1]._type==null) {return null}
        macro_verify(path.ok,prog,expr.at,"optic_get: path must be a literal or immutable constant string")
        var problem=""
        var inscope parts <- optics_parts(path.value,problem)
        macro_verify(problem=="",prog,expr.at,problem)
        var root=clone_type(expr.arguments[0]._type)
        let focus=optics_focus(root,parts,prog,expr.at)
        if(focus==null) {return null}
        if(root.flags.ref || root.canCopy) {
            let access=optics_access(expr.arguments[0],parts)
            return qmacro(_::derive_clone($e(access)))
        }
        root.flags.ref=false;root.flags.constant=false
        let name=make_unique_private_name("__optic_input",expr.at)
        let access=optics_access(qmacro($i(name)),parts)
        var result=qmacro(optics_get_owned($e(expr.arguments[0])) <| $($i(name):$t(root)) : $t(focus) {
            static_if(typeinfo can_copy(type<$t(focus)>)) {return _::derive_clone($e(access))}
            else {return <- _::derive_clone($e(access))}
        })
        result |> force_at(expr.at)
        return result
    }
}
def private optics_edit(prog:ProgramPtr;expr:ExprCallMacro?;over:bool) : ExpressionPtr {
    macro_verify(length(expr.arguments)==3,prog,expr.at,over ? "optic_over expects source, constant path and callback" : "optic_set expects source, constant path and replacement")
    if(expr.arguments[0]._type==null || expr.arguments[2]._type==null) {return null}
    macro_verify(!optics_temporary_projection(expr.arguments[0]),prog,expr.at,"optic: bind the temporary owner to a variable or pass it with the complete field path")
    let path=optics_constant(expr.arguments[1])
    if(!path.ok && expr.arguments[1]._type==null) {return null}
    macro_verify(path.ok,prog,expr.at,"optic: path must be a literal or immutable constant string")
    var problem=""
    var inscope parts <- optics_parts(path.value,problem)
    macro_verify(problem=="",prog,expr.at,problem)
    var root=clone_type(expr.arguments[0]._type)
    let focus=optics_focus(root,parts,prog,expr.at)
    if(focus==null) {return null}
    let owned=!root.flags.ref && !root.canCopy
    root.flags.ref=false;root.flags.constant=false
    let name=make_unique_private_name("__optic_target",expr.at)
    let access=optics_access(qmacro($i(name)),parts)
    var edit:ExpressionPtr
    if(over) {
        let callback=expr.arguments[2]._type
        macro_verify(callback.baseType==Type.tBlock,prog,expr.at,"optic_over: expected a block returning the focus type")
        macro_verify(callback.firstType!=null && !callback.firstType.flags.ref,prog,expr.at,"optic_over: callback must return a value, not a borrowed reference")
        edit=qmacro(optics_modify($e(access),$e(expr.arguments[2])))
    }
    else {
        macro_verify(!optics_temporary_projection(expr.arguments[2]),prog,expr.at,"optic_set: bind the replacement temporary owner to a variable before selecting its field")
        let incoming=expr.arguments[2]._type
        macro_verify(incoming.baseType!=Type.tVoid,prog,expr.at,"optic_set: replacement must have the focus type")
        // Temporaries transfer ownership; borrowed fields/variables are cloned first.
        if(incoming.flags.ref || incoming.canCopy) {edit=qmacro(optics_assign_copy($e(access),$e(expr.arguments[2])))}
        else {edit=qmacro(optics_assign_owned($e(access),$e(expr.arguments[2])))}
    }
    let helper=owned ? "optics_update_owned" : "optics_update_copy"
    var result=qmacro($c(helper)($e(expr.arguments[0]),$(var $i(name):$t(root)) {$e(edit)}))
    result |> force_at(expr.at)
    return result
}
[call_macro(name="optic_set")]
class OpticSet : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {return optics_edit(prog,expr,false)}
}
[call_macro(name="optic_over")]
class OpticOver : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {return optics_edit(prog,expr,true)}
}

// Prisms use the same constant path descriptors, with variant case names
// resolved from the current type. Every cast is guarded by its variant tag.
def private prism_path(root:TypeDeclPtr;parts:array<string>;input:ExpressionPtr;prog:ProgramPtr;at:LineInfo) : tuple<focus:TypeDeclPtr;access:ExpressionPtr;guard:ExpressionPtr> {
    var td=clone_type(root)
    var access=clone_expression(input)
    var guard=qmacro(true)
    for(name in parts) {
        if(td.baseType==Type.tStructure) {
            if(td.structType.flags.isClass || td.structType.parent!=null) {
                macro_error(prog,at,"prism: only plain struct fields and variant cases are supported")
                return (focus=null,access=null,guard=null)
            }
            var found=false
            for(field in td.structType.fields) {
                if(field.name==name) {td=clone_type(field._type);found=true;break}
            }
            if(!found) {
                macro_error(prog,at,"prism: field '{name}' was not found")
                return (focus=null,access=null,guard=null)
            }
            access=qmacro($e(access).$f(name))
        } elif(td.baseType==Type.tVariant) {
            var index=-1
            for(i in range(length(td.argNames))) {if(string(td.argNames[i])==name) {index=i;break}}
            if(index<0) {
                macro_error(prog,at,"prism: variant case '{name}' was not found")
                return (focus=null,access=null,guard=null)
            }
            guard=qmacro($e(guard) && variant_index($e(access))==$v(index))
            td=clone_type(td.argTypes[index])
            if(td.baseType!=Type.tVoid) {access=qmacro($e(access) as $f(name))}
        } else {
            macro_error(prog,at,"prism: cannot traverse '{name}'; only plain struct fields and variant cases are supported")
            return (focus=null,access=null,guard=null)
        }
    }
    td.flags.constant=false;td.flags.ref=false
    return (focus=td,access=access,guard=guard)
}

[call_macro(name="prism")]
class PrismPath : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {
        macro_verify(length(expr.arguments)==1,prog,expr.at,"prism expects one constant field/case path")
        let path=optics_constant(expr.arguments[0])
        if(!path.ok && expr.arguments[0]._type==null) {return null}
        macro_verify(path.ok,prog,expr.at,"prism: path must be a literal or immutable constant string")
        var problem=""
        var inscope parts <- optics_parts(path.value,problem)
        macro_verify(problem=="",prog,expr.at,problem)
        return qmacro($v(path.value))
    }
}
[call_macro(name="prism_then")]
class PrismThen : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {
        macro_verify(length(expr.arguments)==2,prog,expr.at,"prism_then expects two constant field paths")
        let left=optics_constant(expr.arguments[0]);let right=optics_constant(expr.arguments[1])
        if((!left.ok && expr.arguments[0]._type==null) || (!right.ok && expr.arguments[1]._type==null)) {return null}
        macro_verify(left.ok && right.ok,prog,expr.at,"prism_then: paths must be literal or immutable constant strings")
        var problem=""
        var inscope lp <- optics_parts(left.value,problem)
        macro_verify(problem=="",prog,expr.at,problem)
        var inscope rp <- optics_parts(right.value,problem)
        macro_verify(problem=="",prog,expr.at,problem)
        let path=left.value+"."+right.value
        return qmacro($v(path))
    }
}

def private prism_read_macro(prog:ProgramPtr;expr:ExprCallMacro?;matches:bool) : ExpressionPtr {
    macro_verify(length(expr.arguments)==2,prog,expr.at,"prism read expects source and constant path")
    if(expr.arguments[0]._type==null) {return null}
    macro_verify(!optics_temporary_projection(expr.arguments[0]),prog,expr.at,"prism: bind the temporary owner to a variable or pass it with the complete path")
    let path=optics_constant(expr.arguments[1])
    if(!path.ok && expr.arguments[1]._type==null) {return null}
    macro_verify(path.ok,prog,expr.at,"prism: path must be a literal or immutable constant string")
    var problem=""
    var inscope parts <- optics_parts(path.value,problem)
    macro_verify(problem=="",prog,expr.at,problem)
    var root=clone_type(expr.arguments[0]._type)
    let owned=!root.flags.ref && !root.canCopy
    root.flags.ref=false;root.flags.constant=false
    let name=make_unique_private_name("__prism_input",expr.at)
    let selected=prism_path(root,parts,qmacro($i(name)),prog,expr.at)
    if(selected.focus==null) {return null}
    let helper=owned ? "optics_get_owned" : "prism_read"
    var readType=clone_type(root)
    if(!owned) {readType.flags.constant=true}
    var result:ExpressionPtr
    if(matches) {
        result=qmacro($c(helper)($e(expr.arguments[0]),$($i(name):$t(readType)) : bool {return $e(selected.guard)}))
    } else {
        macro_verify(selected.focus.baseType!=Type.tVoid,prog,expr.at,"prism: selected case has no payload; use prism_matches")
        result=qmacro($c(helper)($e(expr.arguments[0]),$($i(name):$t(readType)) : $Option<$t(selected.focus)> {
            static_assert(typeinfo sizeof(type<$t(selected.focus)>)>0,"prism: zero-sized focus has no data; use prism_matches")
            if($e(selected.guard)) {return <- prism_snapshot($e(selected.access))}
            return <- default<$Option<$t(selected.focus)>>
        }))
    }
    result |> force_at(expr.at)
    return result
}
[call_macro(name="prism_try_get")]
class PrismTryGet : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {return prism_read_macro(prog,expr,false)}
}
[call_macro(name="prism_matches")]
class PrismMatches : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {return prism_read_macro(prog,expr,true)}
}

def private prism_edit_macro(prog:ProgramPtr;expr:ExprCallMacro?;over:bool) : ExpressionPtr {
    macro_verify(length(expr.arguments)==3,prog,expr.at,"prism update expects source, constant path and replacement/callback")
    if(expr.arguments[0]._type==null || expr.arguments[2]._type==null) {return null}
    macro_verify(!optics_temporary_projection(expr.arguments[0]),prog,expr.at,"prism: bind the temporary owner to a variable or pass it with the complete path")
    let path=optics_constant(expr.arguments[1])
    if(!path.ok && expr.arguments[1]._type==null) {return null}
    macro_verify(path.ok,prog,expr.at,"prism: path must be a literal or immutable constant string")
    var problem=""
    var inscope parts <- optics_parts(path.value,problem)
    macro_verify(problem=="",prog,expr.at,problem)
    var root=clone_type(expr.arguments[0]._type)
    let owned=!root.flags.ref && !root.canCopy
    root.flags.ref=false;root.flags.constant=false
    let name=make_unique_private_name("__prism_target",expr.at)
    let selected=prism_path(root,parts,qmacro($i(name)),prog,expr.at)
    if(selected.focus==null) {return null}
    macro_verify(selected.focus.baseType!=Type.tVoid,prog,expr.at,"prism: selected case has no payload; use prism_matches")
    var edit:ExpressionPtr
    if(over) {
        let callback=expr.arguments[2]._type
        macro_verify(callback.baseType==Type.tBlock,prog,expr.at,"prism_over: expected a block returning the focus type")
        macro_verify(callback.firstType!=null && !callback.firstType.flags.ref,prog,expr.at,"prism_over: callback must return a value, not a borrowed reference")
        edit=qmacro(optics_modify($e(selected.access),$e(expr.arguments[2])))
    } else {
        macro_verify(!optics_temporary_projection(expr.arguments[2]),prog,expr.at,"prism_set: bind the replacement temporary owner before selecting its field")
        let incoming=expr.arguments[2]._type
        if(incoming.flags.ref || incoming.canCopy) {edit=qmacro(optics_assign_copy($e(selected.access),$e(expr.arguments[2])))}
        else {edit=qmacro(optics_assign_owned($e(selected.access),$e(expr.arguments[2])))}
    }
    let helper=owned ? "optics_update_owned" : "optics_update_copy"
    var result=qmacro($c(helper)($e(expr.arguments[0]),$(var $i(name):$t(root)) {
        static_assert(typeinfo sizeof(type<$t(selected.focus)>)>0,"prism: zero-sized focus has no data; use prism_matches")
        if($e(selected.guard)) {$e(edit)}
    }))
    result |> force_at(expr.at)
    return result
}
[call_macro(name="prism_set")]
class PrismSet : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {return prism_edit_macro(prog,expr,false)}
}
[call_macro(name="prism_over")]
class PrismOver : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {return prism_edit_macro(prog,expr,true)}
}
