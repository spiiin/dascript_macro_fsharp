options gen2
module derive_variant_macros public
require daslib/macro_boost
require daslib/ast
require daslib/ast_boost
require daslib/templates_boost

[call_macro(name="derive_variant_select")]
class DeriveVariantSelect : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {
        macro_verify(length(expr.arguments)==6,prog,expr.at,"derive_variant_select expects six arguments")
        if(expr.arguments[0]._type==null) {return null}
        var vt=clone_type(expr.arguments[0]._type)
        macro_verify(vt.baseType==Type.tVariant,prog,expr.at,"derive_variant_select expects a variant")
        vt.flags.constant=false;vt.flags.ref=false
        var steps:array<ExpressionPtr>
        for(i in range(length(vt.argTypes))) {
            let name=string(vt.argNames[i])
            let ft=vt.argTypes[i]
            var ctor=new ExprMakeVariant(at=expr.at,makeType=clone_type(vt))
            var field=new MakeFieldDecl(at=expr.at,name:=name)
            var readSteps:array<ExpressionPtr>
            if(ft.baseType!=Type.tVoid) {
                field.value=qmacro(derive_json_default(type<$t(ft)>))
                if(!ft.canCopy) {field.flags=MakeFieldDeclFlags.moveSemantics}
                readSteps |> push <| qmacro_expr() {{
                    if(key_exists($e(expr.arguments[2]),"value")) {
                        _::derive_json_read($e(expr.arguments[2])?["value"],$e(expr.arguments[0]) as $f(name),validation_path($e(expr.arguments[3]),"value"),$e(expr.arguments[4]),$e(expr.arguments[5]))
                    } else {derive_json_error($e(expr.arguments[4]),validation_path($e(expr.arguments[3]),"value"),"missing variant payload","json_missing")}
                }}
            } else {
                readSteps |> push <| qmacro_expr() {{
                    if(key_exists($e(expr.arguments[2]),"value")) {derive_json_error($e(expr.arguments[4]),validation_path($e(expr.arguments[3]),"value"),"case has no payload","json_variant_payload")}
                }}
            }
            ctor.variants |> emplace(field)
            steps |> push <| qmacro_expr() {{
                if($e(expr.arguments[1])==$v(name)) {
                    static_if(typeinfo can_delete($e(expr.arguments[0]))) {delete $e(expr.arguments[0])}
                    $e(expr.arguments[0]) <- $e(ctor)
                    $b(readSteps)
                    return
                }
            }}
        }
        steps |> push <| qmacro_expr() {derive_json_error($e(expr.arguments[4]),validation_path($e(expr.arguments[3]),"case"),"unknown variant case","json_variant")}
        var result=qmacro_expr() {{$b(steps)}}
        result |> force_at(expr.at)
        return result
    }
}
[call_macro(name="derive_variant_equal")]
class DeriveVariantEqual : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {
        macro_verify(length(expr.arguments)==2,prog,expr.at,"derive_variant_equal expects two arguments")
        if(expr.arguments[0]._type==null) {return null}
        let vt=expr.arguments[0]._type
        macro_verify(vt.baseType==Type.tVariant,prog,expr.at,"derive_variant_equal expects a variant")
        var steps:array<ExpressionPtr>
        for(i in range(length(vt.argTypes))) {
            let name=string(vt.argNames[i])
            if(vt.argTypes[i].baseType==Type.tVoid) {
                steps |> push <| qmacro_expr() {if(variant_index($e(expr.arguments[0]))==$v(i)) {return true}}
            } else {
                steps |> push <| qmacro_expr() {if(variant_index($e(expr.arguments[0]))==$v(i)) {return _::derive_equal($e(expr.arguments[0]) as $f(name),$e(expr.arguments[1]) as $f(name))}}
            }
        }
        steps |> push <| qmacro_expr() {panic("derive: invalid variant tag")}
        var result=qmacro_expr() {{$b(steps)}}
        return result
    }
}


[call_macro(name="derive_variant_clone")]
class DeriveVariantClone : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {
        macro_verify(length(expr.arguments)==1,prog,expr.at,"derive_variant_clone expects one argument")
        if(expr.arguments[0]._type==null) {return null}
        var vt=clone_type(expr.arguments[0]._type)
        macro_verify(vt.baseType==Type.tVariant,prog,expr.at,"derive_variant_clone expects a variant")
        vt.flags.constant=false;vt.flags.ref=false
        var steps:array<ExpressionPtr>
        for(i in range(length(vt.argTypes))) {
            let name=string(vt.argNames[i])
            let ft=vt.argTypes[i]
            var ctor=new ExprMakeVariant(at=expr.at,makeType=clone_type(vt))
            var field=new MakeFieldDecl(at=expr.at,name:=name)
            if(ft.baseType!=Type.tVoid) {
                field.value=qmacro(_::derive_clone($e(expr.arguments[0]) as $f(name)))
                if(!ft.canCopy) {field.flags=MakeFieldDeclFlags.moveSemantics}
            }
            ctor.variants |> emplace(field)
            if(i==length(vt.argTypes)-1) {
                steps |> push <| qmacro_expr() {if(variant_index($e(expr.arguments[0]))!=$v(i)) {panic("derive_clone: invalid variant tag")}}
                if(vt.canCopy) {steps |> push <| qmacro_expr() {return $e(ctor)}}
                else {steps |> push <| qmacro_expr() {return <- $e(ctor)}}
            } elif(vt.canCopy) {
                steps |> push <| qmacro_expr() {if(variant_index($e(expr.arguments[0]))==$v(i)) {return $e(ctor)}}
            } else {
                steps |> push <| qmacro_expr() {if(variant_index($e(expr.arguments[0]))==$v(i)) {return <- $e(ctor)}}
            }
        }
        var result=qmacro_expr() {{$b(steps)}}
        result |> force_at(expr.at)
        return result
    }
}

[call_macro(name="derive_variant_diff")]
class DeriveVariantDiff : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {
        macro_verify(length(expr.arguments)==4,prog,expr.at,"derive_variant_diff expects four arguments")
        if(expr.arguments[0]._type==null) {return null}
        let vt=expr.arguments[0]._type
        macro_verify(vt.baseType==Type.tVariant,prog,expr.at,"derive_variant_diff expects a variant")
        var steps:array<ExpressionPtr>
        for(i in range(length(vt.argTypes))) {
            let name=string(vt.argNames[i])
            if(vt.argTypes[i].baseType==Type.tVoid) {
                steps |> push <| qmacro_expr() {if(variant_index($e(expr.arguments[0]))==$v(i)) {return}}
            } else {
                steps |> push <| qmacro_expr() {{
                    if(variant_index($e(expr.arguments[0]))==$v(i)) {
                        _::derive_diff_into($e(expr.arguments[0]) as $f(name),$e(expr.arguments[1]) as $f(name),diff_path($e(expr.arguments[2]),"value"),$e(expr.arguments[3]))
                        return
                    }
                }}
            }
        }
        steps |> push <| qmacro_expr() {panic("derive_diff: invalid variant tag")}
        var result=qmacro_expr() {{$b(steps)}}
        result |> force_at(expr.at)
        return result
    }
}

[call_macro(name="derive_variant_patch")]
class DeriveVariantPatch : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {
        macro_verify(length(expr.arguments)==5,prog,expr.at,"derive_variant_patch expects five arguments")
        if(expr.arguments[0]._type==null) {return null}
        let vt=expr.arguments[0]._type
        macro_verify(vt.baseType==Type.tVariant,prog,expr.at,"derive_variant_patch expects a variant")
        var steps:array<ExpressionPtr>
        for(i in range(length(vt.argTypes))) {
            let name=string(vt.argNames[i])
            if(vt.argTypes[i].baseType==Type.tVoid) {
                steps |> push <| qmacro_expr() {if(variant_index($e(expr.arguments[0]))==$v(i)) {return}}
            } else {
                steps |> push <| qmacro_expr() {{
                    if(variant_index($e(expr.arguments[0]))==$v(i)) {
                        _::derive_patch_into($e(expr.arguments[0]) as $f(name),$e(expr.arguments[1]) as $f(name),$e(expr.arguments[2]) as $f(name),validation_path($e(expr.arguments[3]),"value"),$e(expr.arguments[4]))
                        return
                    }
                }}
            }
        }
        steps |> push <| qmacro_expr() {panic("derive_patch: invalid variant tag")}
        var result=qmacro_expr() {{$b(steps)}}
        result |> force_at(expr.at)
        return result
    }
}
