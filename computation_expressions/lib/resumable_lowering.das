options gen2
module resumable_lowering public
require daslib/ast_boost
require daslib/templates_boost

def private ce_resumable_owns_type(t:TypeDeclPtr) : bool {
    if(t==null || t.flags.ref || t.baseType==Type.tPointer || t.baseType==Type.tBlock
        || t.baseType==Type.tLambda || t.baseType==Type.tIterator || t.baseType==Type.tHandle) {return false}
    if(t.baseType==Type.tStructure) {
        for(field in t.structType.fields) {if(!ce_resumable_owns_type(field._type)) {return false}}
    } elif(t.baseType==Type.tTuple || t.baseType==Type.tVariant) {
        for(field in t.argTypes) {if(!ce_resumable_owns_type(field)) {return false}}
    }
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
def ce_resumable_scope(node:ExpressionPtr; builder:string; var error:string&) : ExpressionPtr {
    if (node==null) {return qmacro_block() {}}
    var blk=qmacro_block() {} as ExprBlock
    if (node is ExprBlock) {blk=clone_expression(node) as ExprBlock}
    else {blk.list |> push <| clone_expression(node)}
    if(!empty(blk.finalList)) {error="task: native finally is unsupported; use try_finally";return blk}
    var output:array<ExpressionPtr>
    for(index in range(length(blk.list))) {
        var stmt=clone_expression(blk.list[index])
        var binding:ExpressionPtr
        if(stmt is ExprLet && length((stmt as ExprLet).variables)==1) {binding=(stmt as ExprLet).variables[0].init}
        elif(stmt is ExprCall) {binding=stmt}
        if(binding!=null && binding is ExprCall && (binding as ExprCall).name=="bind") {
            let call=binding as ExprCall
            if(length(call.arguments)!=1) {error="task: expected source |> bind";return blk}
            if(call.arguments[0] is ExprCall && (call.arguments[0] as ExprCall).name=="and_bind") {
                error="task: and_bind is not supported yet; use sequential bind";return blk
            }
            let event=make_unique_private_name("__await_event",stmt.at)
            var tail:array<ExpressionPtr>
            if(stmt is ExprLet) {
                var declaration=clone_expression(stmt) as ExprLet
                if(declaration.variables[0]._type.flags.ref) {
                    declaration.variables[0].init=qmacro(ce_await_borrow_value($i(builder),$i(event)))
                } else {declaration.variables[0].init=qmacro(ce_await_value($i(builder),$i(event)))}
                tail |> push <| declaration
            }
            for(i in range(index+1,length(blk.list))) {tail |> push <| clone_expression(blk.list[i])}
            let rest=ce_resumable_scope(qmacro_block() {$b(tail);},builder,error)
            var loop=qmacro_expr() {
                for($i(event) in ce_await_source($i(builder),$e(call.arguments[0]))) {
                    if(!$i(event).ready) {yield ce_await_pending($i(builder))}
                    elif(ce_await_failed($i(builder),$i(event))) {yield ce_await_failure($i(builder),$i(event))}
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
            if(ret.subexpr==null || ret.returnFlags.moveSemantics) {error="task: use 'return value' with a copyable payload";return blk}
            output |> push <| qmacro_expr() {yield ce_await_return($i(builder),$e(ret.subexpr))}
        } elif(stmt is ExprIfThenElse) {
            var branch=stmt as ExprIfThenElse
            branch.if_true=ce_resumable_scope(branch.if_true,builder,error)
            branch.if_false=ce_resumable_scope(branch.if_false,builder,error)
            output |> push <| branch
        } elif(stmt is ExprFor) {
            var loop=stmt as ExprFor
            loop.body=ce_resumable_scope(loop.body,builder,error)
            output |> push <| loop
        } elif(stmt is ExprWhile) {
            var loop=stmt as ExprWhile
            loop.body=ce_resumable_scope(loop.body,builder,error)
            output |> push <| loop
        } elif(stmt is ExprBlock) {
            output |> push <| ce_resumable_scope(stmt,builder,error)
        } elif(stmt is ExprCall && ((stmt as ExprCall).name=="try_finally" || (stmt as ExprCall).name=="try_with")) {
            var call=stmt as ExprCall
            // Cleanup is ordinary code; a recovery handler is another CE body.
            for(i in range(length(call.arguments))) {
                if(i==1 && call.name=="try_finally") {continue}
                if(call.arguments[i] is ExprMakeBlock) {
                    var mb=call.arguments[i] as ExprMakeBlock
                    var original=mb._block as ExprBlock
                    var lowered=ce_resumable_scope(mb._block,builder,error) as ExprBlock
                    original.list |> clear()
                    for(entry in lowered.list) {original.list |> push <| clone_expression(entry)}
                }
            }
            output |> push <| call
        } elif(stmt is ExprYield) {
            error="task: use source |> bind to await; yield is not supported";return blk
        } else {output |> push <| stmt}
    }
    return qmacro_block() {$b(output);}
}
