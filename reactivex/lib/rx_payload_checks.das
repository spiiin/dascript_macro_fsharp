options gen2
module rx_payload_checks public
require daslib/ast_boost public
require daslib/templates_boost

def private rx_owns_payload(t:TypeDeclPtr) : bool {
    if(t==null || t.flags.ref || t.baseType==Type.tPointer || t.baseType==Type.tBlock
        || t.baseType==Type.tLambda || t.baseType==Type.tIterator || t.baseType==Type.tHandle) {return false}
    if(t.baseType==Type.tStructure) {
        for(field in t.structType.fields) {if(!rx_owns_payload(field._type)) {return false}}
    } elif(t.baseType==Type.tTuple || t.baseType==Type.tVariant) {
        for(field in t.argTypes) {if(!rx_owns_payload(field)) {return false}}
    } elif(t.baseType==Type.tArray) {return rx_owns_payload(t.firstType)}
    elif(t.baseType==Type.tTable) {return rx_owns_payload(t.firstType) && rx_owns_payload(t.secondType)}
    return true
}
[typeinfo_macro(name="rx_payload")]
class RxPayload : AstTypeInfoMacro {
    def override getAstChange(expr:ExprTypeInfo?;var errors:das_string) : ExpressionPtr {
        if(expr.subexpr==null || expr.subexpr._type==null || expr.subexpr._type.isAutoOrAlias) {return null}
        if(!rx_owns_payload(expr.subexpr._type)) {
            errors:="rx: payload must own its data; nested pointers, references, handles, callbacks and iterators are unsupported"
            return null
        }
        return <- new ExprConstBool(at=expr.at,value=true)
    }
}

// Nested generic source types must not export their temporary deduction aliases
// (T/U) into the next operator's inference scope.
def private rx_normal_type(original:TypeDeclPtr) : TypeDeclPtr {
    var result=clone_type(original)
    result.alias:=""
    if(result.firstType!=null) {result.firstType=rx_normal_type(result.firstType)}
    if(result.secondType!=null) {result.secondType=rx_normal_type(result.secondType)}
    for(field in result.argTypes) {field=rx_normal_type(field)}
    return result
}
[typeinfo_macro(name="rx_normalized")]
class RxNormalized : AstTypeInfoMacro {
    def override getAstChange(expr:ExprTypeInfo?;var errors:das_string) : ExpressionPtr {
        if(expr.subexpr==null || expr.subexpr._type==null || expr.subexpr._type.isAutoOrAlias) {return null}
        let clean=rx_normal_type(expr.subexpr._type)
        return qmacro_expr() {reinterpret<$t(clean)>($e(expr.subexpr))}
    }
}
