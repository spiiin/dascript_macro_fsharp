options gen2
module resumable_lowering public
require daslib/ast_boost
require daslib/templates_boost
require strings

// Native AOT generator fields must have unique names even for locals declared
// in different lexical loops. Respect shadowing when rewriting their tail.
[macro_interface]
class CeTaskLocalRename : AstVisitor {
    original:string
    replacement:string
    hidden:bool
    scopes:array<bool>
    def save() {scopes |> push(hidden)}
    def restore() {hidden=scopes[length(scopes)-1];scopes |> pop()}
    def override preVisitExprBlock(blk:ExprBlock?) {
        self.save()
        for(arg in blk.arguments) {if(arg.name==original) {hidden=true}}
    }
    def override visitExprBlock(var blk:ExprBlock?) : ExpressionPtr {self.restore();return blk}
    def override visitExprLetVariable(expr:ExprLet?;var arg:VariablePtr;lastArg:bool) : VariablePtr {
        if(arg.name==original) {hidden=true}
        return arg
    }
    def override preVisitExprFor(expr:ExprFor?) {self.save()}
    def override preVisitExprForStack(expr:ExprFor?) {
        for(name in expr.iterators) {if(name==original) {hidden=true}}
    }
    def override visitExprFor(var expr:ExprFor?) : ExpressionPtr {self.restore();return expr}
    def override visitExprVar(var expr:ExprVar?) : ExpressionPtr {
        if(!hidden && expr.name==original) {
            var renamed=qmacro($i(replacement));renamed.at=expr.at;return renamed
        }
        return expr
    }
}
def private ce_task_rename_tail(body:ExpressionPtr;original,replacement:string) : ExpressionPtr {
    var visitor=new CeTaskLocalRename(original=original,replacement=replacement)
    var result:ExpressionPtr
    make_visitor(*visitor) $(adapter) {result=visit(body,adapter)}
    unsafe {delete visitor}
    return result
}

def private ce_task_wrap_loop(loop:ExpressionPtr;control:string) : ExpressionPtr {
    var outer=qmacro_expr() {for($i(control) in ce_task_loop_scope()) {}}
    outer.at=loop.at
    outer.at.column+=1
    var body=qmacro_block() {} as ExprBlock
    body.at=outer.at
    body.list |> push <| clone_expression(loop)
    (outer as ExprFor).body=body
    return outer
}

[typeinfo_macro(name="ce_has_resumable_zero")]
class CeHasResumableZero : AstTypeInfoMacro {
    def override getAstChange(expr:ExprTypeInfo?; var errors:das_string) : ExpressionPtr {
        if(expr.subexpr==null || expr.subexpr._type==null) {return null}
        let t=expr.subexpr._type
        return <- new ExprConstBool(at=expr.at,value=!(t.baseType==Type.tStructure && t.structType.name=="CeResumableNoZero" && t.structType._module.name=="builder_protocol"))
    }
}

def private ce_resumable_owns_type(t:TypeDeclPtr) : bool {
    if(t==null || t.flags.ref || t.baseType==Type.tPointer || t.baseType==Type.tBlock
        || t.baseType==Type.tLambda || t.baseType==Type.tIterator || t.baseType==Type.tHandle) {return false}
    if(t.baseType==Type.tStructure) {
        for(field in t.structType.fields) {if(!ce_resumable_owns_type(field._type)) {return false}}
    } elif(t.baseType==Type.tTuple || t.baseType==Type.tVariant) {
        for(field in t.argTypes) {if(!ce_resumable_owns_type(field)) {return false}}
    } elif(t.baseType==Type.tArray) {return ce_resumable_owns_type(t.firstType)}
    elif(t.baseType==Type.tTable) {return ce_resumable_owns_type(t.firstType) && ce_resumable_owns_type(t.secondType)}
    return true
}

[typeinfo_macro(name="ce_resumable_payload")]
class ResumablePayload : AstTypeInfoMacro {
    def override getAstChange(expr:ExprTypeInfo?; var errors:das_string) : ExpressionPtr {
        if(expr.subexpr==null || expr.subexpr._type==null || expr.subexpr._type.isAutoOrAlias) {return null}
        if(!ce_resumable_owns_type(expr.subexpr._type)) {
            errors:="task: payload must own its data; pointers, references, executable captures and iterators are unsupported"
            return null
        }
        return <- new ExprConstBool(at=expr.at,value=true)
    }
}

// A resumable builder supplies events, await adapters and return conversion.
// The sequence lowering subsequently adds protected source/resource ownership.
def ce_resumable_scope(node:ExpressionPtr; builder:string; var error:string&;
    await_source:block<(source:ExpressionPtr;isAwait:bool):ExpressionPtr>; control:string="") : ExpressionPtr {
    if (node==null) {return qmacro_block() {}}
    var blk=qmacro_block() {} as ExprBlock
    if (node is ExprBlock) {blk=clone_expression(node) as ExprBlock}
    else {blk.list |> push <| clone_expression(node)}
    if(!empty(blk.finalList)) {error="task: native finally is unsupported; use try_finally";return blk}
    var output:array<ExpressionPtr>
    var index=0
    while(index<length(blk.list)) {
        var stmt=clone_expression(blk.list[index])
        if(stmt is ExprLet && length((stmt as ExprLet).variables)==1) {
            var local=(stmt as ExprLet).variables[0]
            let original=string(local.name)
            if(!starts_with(original,"__task_local_")) {
                let replacement=make_unique_private_name("__task_local_{original}",stmt.at)
                local.name := replacement
                if(index+1<length(blk.list)) {
                    var tail:array<ExpressionPtr>
                    for(i in range(index+1,length(blk.list))) {tail |> push <| clone_expression(blk.list[i])}
                    let renamed=ce_task_rename_tail(qmacro_block() {$b(tail);},original,replacement)
                    blk.list.resize(index+1)
                    blk.list |> push <| renamed
                }
            }
        }
        var binding:ExpressionPtr
        if(stmt is ExprLet && length((stmt as ExprLet).variables)==1) {binding=(stmt as ExprLet).variables[0].init}
        elif(stmt is ExprCall) {binding=stmt}
        if(stmt is ExprLet && binding!=null) {
            var decl=stmt as ExprLet
            var local=decl.variables[0]
            if(local.flags.inScope || decl.letFlags.inScope || local.flags.init_via_move || local.flags.init_via_clone) {
                let initial=clone_expression(binding)
                local.flags.inScope=false;decl.letFlags.inScope=false
                local.flags.init_via_move=false;local.flags.init_via_clone=false
                local._type.flags.ref=true
                local.init=qmacro(use_task_local($e(initial)))
                binding=local.init
            }
        }
        if(binding!=null && binding is ExprCall && (binding as ExprCall).name=="bind") {
            let call=binding as ExprCall
            if(length(call.arguments)!=1) {error="task: expected source |> bind";return blk}
            let source=invoke(await_source,call.arguments[0],true)
            if(!empty(error)) {return blk}
            let event=make_unique_private_name("__await_event",stmt.at)
            var tail:array<ExpressionPtr>
            if(stmt is ExprLet) {
                var declaration=clone_expression(stmt) as ExprLet
                if(declaration.variables[0]._type.flags.ref) {
                    declaration.variables[0].init=qmacro(ce_await_borrow_value($i(builder),$i(event)))
                } else {declaration.variables[0].init=qmacro(ce_await_value($i(builder),$i(event)))}
                declaration.variables[0].init.at=stmt.at
                tail |> push <| declaration
            }
            for(i in range(index+1,length(blk.list))) {tail |> push <| clone_expression(blk.list[i])}
            let rest=ce_resumable_scope(qmacro_block() {$b(tail);},builder,error,await_source,control)
            var loop=qmacro_expr() {
                for($i(event) in $e(source)) {
                    if(!$i(event).ready) {yield <- ce_await_pending($i(builder))}
                    elif(ce_await_failed($i(builder),$i(event))) {yield <- ce_await_failure($i(builder),$i(event))}
                    else {$e(rest)}
                }
            }
            loop.at=stmt.at
            (loop as ExprFor).body.at=stmt.at
            output |> push <| loop
            return qmacro_block() {$b(output);}
        }
        if(stmt is ExprReturn) {
            let ret=stmt as ExprReturn
            if(ret.subexpr!=null && ret.subexpr is ExprCall && (ret.subexpr as ExprCall).name=="return_from") {
                let source=ret.subexpr as ExprCall
                if(length(source.arguments)!=1) {error="task: expected 'return source |> return_from'";return blk}
                let name=make_unique_private_name("__await_return_from",stmt.at)
                let forwarded=qmacro_block() {
                    var $i(name) & = $e(source.arguments[0]) |> bind
                    return <- $i(name)
                }
                let lowered=ce_resumable_scope(forwarded,builder,error,await_source,control) as ExprBlock
                for(entry in lowered.list) {output |> push <| clone_expression(entry)}
            } elif(ret.subexpr==null) {
                output |> push <| qmacro_expr() {yield <- ce_await_return($i(builder),CeUnit())}
            } elif(ret.returnFlags.moveSemantics) {
                output |> push <| qmacro_expr() {yield <- ce_await_return_move($i(builder),$e(ret.subexpr))}
            } else {output |> push <| qmacro_expr() {yield <- ce_await_return($i(builder),$e(ret.subexpr))}}
        } elif(stmt is ExprIfThenElse) {
            var branch=stmt as ExprIfThenElse
            branch.if_true=ce_resumable_scope(branch.if_true,builder,error,await_source,control)
            branch.if_false=ce_resumable_scope(branch.if_false,builder,error,await_source,control)
            output |> push <| branch
        } elif(stmt is ExprFor) {
            var loop=stmt as ExprFor
            let nested=make_unique_private_name("__task_for_control",stmt.at)
            let body=ce_resumable_scope(loop.body,builder,error,await_source,nested)
            loop.body=qmacro_block() {ce_task_loop_signal($i(nested),0);$e(body)}
            for(source in loop.sources) {
                let original=invoke(await_source,clone_expression(source),false)
                source=qmacro(invoke($ {
                    static_if((typeinfo can_copy($e(original))) || (typeinfo ce_source_is_borrowed($e(original)))) {
                        return <- ce_task_loop_source($e(original),$i(nested))
                    } else {return <- ce_task_loop_source_owned($e(original),$i(nested))}
                }))
            }
            output |> push <| ce_task_wrap_loop(loop,nested)
        } elif(stmt is ExprWhile) {
            var loop=stmt as ExprWhile
            let nested=make_unique_private_name("__task_while_control",stmt.at)
            let body=ce_resumable_scope(loop.body,builder,error,await_source,nested)
            loop.body=qmacro_block() {ce_task_loop_signal($i(nested),0);$e(body)}
            let condition=clone_expression(loop.cond)
            loop.cond=qmacro(ce_task_loop_not_broken($i(nested)) && $e(condition))
            output |> push <| ce_task_wrap_loop(loop,nested)
        } elif(stmt is ExprBlock) {
            output |> push <| ce_resumable_scope(stmt,builder,error,await_source,control)
        } elif(stmt is ExprCall && ((stmt as ExprCall).name=="try_finally" || (stmt as ExprCall).name=="try_with")) {
            var call=stmt as ExprCall
            // Cleanup is ordinary code; a recovery handler is another CE body.
            for(i in range(length(call.arguments))) {
                if(i==1 && call.name=="try_finally") {continue}
                if(call.arguments[i] is ExprMakeBlock) {
                    var mb=call.arguments[i] as ExprMakeBlock
                    var original=mb._block as ExprBlock
                    var lowered=ce_resumable_scope(mb._block,builder,error,await_source,control) as ExprBlock
                    original.list |> clear()
                    for(entry in lowered.list) {original.list |> push <| clone_expression(entry)}
                }
            }
            output |> push <| call
        } elif(stmt is ExprBreak || stmt is ExprContinue) {
            if(empty(control)) {error="task: break/continue requires a surrounding CE loop";return blk}
            let signal=stmt is ExprBreak ? 1 : 2
            output |> push <| qmacro(ce_task_loop_signal($i(control),$v(signal)))
            return qmacro_block() {$b(output);}
        } elif(stmt is ExprCall && (stmt as ExprCall).name=="yield_from") {
            let call=stmt as ExprCall
            if(length(call.arguments)!=1) {error="async sequence: expected source |> yield_from";return blk}
            let event=make_unique_private_name("__await_yield_from",stmt.at)
            var loop=qmacro_expr() {
                for($i(event) in ce_await_yield_from($i(builder),$e(call.arguments[0]))) {
                    yield <- $i(event)
                }
            }
            loop.at=stmt.at
            (loop as ExprFor).body.at=stmt.at
            output |> push <| loop
        } elif(stmt is ExprYield) {
            let item=stmt as ExprYield
            var emitted:ExpressionPtr
            if(item.returnFlags.moveSemantics) {
                emitted=qmacro_expr() {yield <- ce_await_yield_move($i(builder),$e(item.subexpr))}
            } else {emitted=qmacro_expr() {yield <- ce_await_yield($i(builder),$e(item.subexpr))}}
            emitted.at=stmt.at
            (emitted as ExprYield).subexpr.at=stmt.at
            output |> push <| emitted
        } else {output |> push <| stmt}
        // A structured statement may have signalled break/continue in a nested
        // await/resource generator. Keep lexical declarations in the same scope
        // and guard the whole remaining continuation, including source factories.
        if(!empty(control) && index+1<length(blk.list) && (stmt is ExprIfThenElse || stmt is ExprBlock || stmt is ExprFor || stmt is ExprWhile
            || (stmt is ExprCall && ((stmt as ExprCall).name=="try_finally" || (stmt as ExprCall).name=="try_with")))) {
            var tail:array<ExpressionPtr>
            for(i in range(index+1,length(blk.list))) {tail |> push <| clone_expression(blk.list[i])}
            let rest=ce_resumable_scope(qmacro_block() {$b(tail);},builder,error,await_source,control)
            output |> push <| qmacro_expr() {if(ce_task_loop_active($i(control))) {$e(rest)}}
            return qmacro_block() {$b(output);}
        }
        index++
    }
    return qmacro_block() {$b(output);}
}
