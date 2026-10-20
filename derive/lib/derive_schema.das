options gen2
module derive_schema public
require daslib/macro_boost
require daslib/ast_boost
require daslib/templates_boost
require daslib/json_boost
require strings
require math

// Schema generation runs at compile time, without constructing model values.
def private schema_quote(text:string) : string {
    var node=JV(text)
    let result=write_json(node)
    delete_json(node)
    return result
}
def private schema_join(parts:array<string>) : string {
    var text=""
    for(part,i in parts,range(length(parts))) {if(i!=0) {text+=","};text+=part}
    return text
}
def private schema_object(parts:array<string>) : string {return "\{"+schema_join(parts)+"\}"}
def private schema_array(parts:array<string>) : string {return "["+schema_join(parts)+"]"}
def private schema_attr(name,value:string) : string {return schema_quote(name)+":"+value}
def private schema_typed(name:string) : string {return "\{\"type\":"+schema_quote(name)+"\}"}
def private schema_literal(value:RttiValue) : string {
    if(value is tString) {return schema_quote(value as tString)}
    if(value is tBool) {return value as tBool ? "true" : "false"}
    if(value is tInt) {return "{value as tInt:d}"}
    if(value is tUInt) {return "{value as tUInt:d}"}
    if(value is tInt64) {return "{value as tInt64:d}"}
    if(value is tUInt64) {return "{value as tUInt64:d}"}
    var node=JV(value is tFloat ? double(value as tFloat) : value as tDouble)
    let result=write_json(node);delete_json(node);return result
}
def private schema_init(init:ExpressionPtr) : string {
    if(init==null) {return ""}
    if(init is ExprConstString) {return schema_quote(string((init as ExprConstString).value))}
    if(init is ExprConstBool) {return (init as ExprConstBool).getValue ? "true" : "false"}
    if(init is ExprConstInt) {return "{(init as ExprConstInt).getValue:d}"}
    if(init is ExprConstUInt) {return "{(init as ExprConstUInt).getValue:d}"}
    if(init is ExprConstInt64) {return "{(init as ExprConstInt64).getValue:d}"}
    if(init is ExprConstUInt64) {return "{(init as ExprConstUInt64).getValue:d}"}
    if(init is ExprConstFloat) {return schema_literal(RttiValue(tFloat=(init as ExprConstFloat).getValue))}
    if(init is ExprConstDouble) {return schema_literal(RttiValue(tDouble=(init as ExprConstDouble).getValue))}
    if(init is ExprConstEnumeration) {return schema_quote(string((init as ExprConstEnumeration).value))}
    return ""
}
struct SchemaState {strict:bool;defs:table<string;string>;order:array<string>;error:string}

def private schema_nullable(td:TypeDeclPtr) : bool {
    return (td.baseType==Type.tVariant && length(td.argTypes)>=2 && td.argTypes[0].baseType==Type.tVoid &&
        ((length(td.argNames)==2 && td.argNames[0]=="none" && td.argNames[1]=="some") ||
         (length(td.argNames)==3 && td.argNames[0]=="missing" && td.argNames[1]=="null_value" && td.argNames[2]=="present" &&
          td.argTypes[1].baseType==Type.tStructure && td.argTypes[1].structType.name=="JsonNull" && td.argTypes[1].structType._module.name=="derive_types")))
}
def private schema_payload(td:TypeDeclPtr) : TypeDeclPtr {
    var result=clone_type(td)
    while(schema_nullable(result)) {result=clone_type(result.argTypes[length(result.argTypes)-1])}
    return result
}
def private schema_field(td:TypeDeclPtr;annotations:AnnotationArgumentList;var state:SchemaState;depth:int) : string {
    var inscope parts:array<string>
    var inscope all:array<string>
    all |> push(schema_type(td,state,depth+1))
    var inscope checks:array<string>
    var minLen=-1
    var maxLen=-1
    let payload=schema_payload(td)
    for(annotation in annotations) {
        let name=string(annotation.name)
        let value=get_annotation_argument_value(annotation)
        if(name=="validate_min" || name=="validate_max") {
            let key=name=="validate_min" ? "minimum" : "maximum"
            if(payload.baseType==Type.tFloat) {parts |> push(schema_attr("x-das-"+key,schema_literal(value)))}
            else {checks |> push(schema_attr(key,schema_literal(value)))}
        } elif(name=="validate_non_empty" && value is tBool && value as tBool) {minLen=max(minLen,1)}
        elif(name=="validate_min_length") {minLen=max(minLen,value as tInt)}
        elif(name=="validate_max_length") {maxLen=value as tInt}
        elif(name=="validate_check" || name=="validate_each" || name=="validate_unique_by") {
            parts |> push(schema_attr("x-das-"+name,schema_quote(value as tString)))
        } elif(name=="builder_required" && value is tBool && value as tBool) {
            parts |> push(schema_attr("x-das-builder-required","true"))
        }
    }
    if(minLen>=0 || maxLen>=0) {
        let isString=payload.baseType==Type.tString
        // daScript length(string) counts bytes, JSON Schema minLength counts codepoints.
        if(isString) {
            if(minLen>=0) {parts |> push(schema_attr("x-das-byteMinLength","{minLen}"))}
            if(maxLen>=0) {parts |> push(schema_attr("x-das-byteMaxLength","{maxLen}"))}
            if(minLen>=1) {checks |> push(schema_attr("minLength","1"))}
        } else {
            if(minLen>=0) {checks |> push(schema_attr("minItems","{minLen}"))}
            if(maxLen>=0) {checks |> push(schema_attr("maxItems","{maxLen}"))}
        }
    }
    if(length(checks)>0) {all |> push(schema_object(checks))}
    parts |> push(schema_attr("allOf",schema_array(all)))
    return schema_object(parts)
}
def private schema_struct(st:StructurePtr;var state:SchemaState;depth:int) : string {
    let id=string(st._module.name)+"::"+string(st.name)
    let ref="\{\"$ref\":"+schema_quote("#/$defs/"+replace(replace(id,"~","~0"),"/","~1"))+"\}"
    if(key_exists(state.defs,id)) {return ref}
    if(length(state.order)>=256) {state.error="derive schema: type graph exceeds 256 structures";return "false"}
    var json=false
    var custom=""
    for(annotation in st.annotations) {
        if(annotation.annotation.name=="derive") {
            let opt=find_arg(annotation.arguments,"json")
            json=opt is tBool && opt as tBool
            let check=find_arg(annotation.arguments,"check")
            if(check is tString) {custom=check as tString}
        }
    }
    if(!json) {state.error="derive schema: struct {st.name} requires [derive(json=true)]; custom encoders need a manually authored schema";return "false"}
    // Register before descending so recursive arrays become references.
    state.defs[id]="false";state.order |> push(id)
    var inscope properties:array<string>
    var inscope required:array<string>
    for(field in st.fields) {
        var name=string(field.name)
        var skip=false
        var needed=true
        var defaultValue=""
        for(annotation in field.annotation) {
            let key=string(annotation.name)
            let value=get_annotation_argument_value(annotation)
            if(key=="json_name") {name=value as tString}
            elif(key=="json_skip") {skip=value as tBool}
            elif(key=="json_required") {needed=value as tBool}
            elif(key=="json_default") {defaultValue=schema_literal(value)}
        }
        if(skip) {continue}
        if(defaultValue!="") {needed=false}
        if(needed) {required |> push(schema_quote(name))}
        if(defaultValue=="") {defaultValue=schema_init(field.init)}
        var inscope property:array<string>
        var inscope constraints:array<string>
        constraints |> push(schema_field(field._type,field.annotation,state,depth+1))
        property |> push(schema_attr("allOf",schema_array(constraints)))
        if(defaultValue!="") {property |> push(schema_attr("default",defaultValue))}
        elif(field.init!=null) {property |> push(schema_attr("x-das-native-default","true"))}
        properties |> push(schema_attr(name,schema_object(property)))
    }
    var inscope parts:array<string>
    parts |> push(schema_attr("type",schema_quote("object")))
    parts |> push(schema_attr("properties",schema_object(properties)))
    parts |> push(schema_attr("required",schema_array(required)))
    parts |> push(schema_attr("additionalProperties",state.strict ? "false" : "true"))
    if(custom!="") {parts |> push(schema_attr("x-das-check",schema_quote(custom)))}
    state.defs[id]=schema_object(parts)
    return ref
}
def private schema_type(td:TypeDeclPtr;var state:SchemaState;depth:int) : string {
    if(depth>96) {state.error="derive schema: type nesting exceeds 96 levels";return "false"}
    if(td.baseType==Type.tFixedArray) {
        let inner=td.firstType
        let count=td.fixedDim
        var inscope parts:array<string>
        parts |> push(schema_attr("type",schema_quote("array")))
        parts |> push(schema_attr("items",schema_type(inner,state,depth+1)))
        parts |> push(schema_attr("minItems","{count}"));parts |> push(schema_attr("maxItems","{count}"))
        return schema_object(parts)
    }
    if(td.baseType==Type.tArray) {
        var inscope parts:array<string>
        parts |> push(schema_attr("type",schema_quote("array")))
        parts |> push(schema_attr("items",schema_type(td.firstType,state,depth+1)))
        return schema_object(parts)
    }
    if(td.baseType==Type.tStructure) {return schema_struct(td.structType,state,depth+1)}
    if(td.baseType==Type.tString) {return schema_typed("string")}
    if(td.baseType==Type.tBool) {return schema_typed("boolean")}
    if(td.isEnumT) {
        var inscope names:array<string>
        for(member in td.enumType.list) {names |> push(schema_quote(string(member.name)))}
        return "\{\"type\":\"string\",\"enum\":"+schema_array(names)+"\}"
    }
    if(td.baseType==Type.tVariant) {
        var inscope alternatives:array<string>
        if(schema_nullable(td)) {
            alternatives |> push(schema_typed("null"))
            alternatives |> push(schema_type(td.argTypes[length(td.argTypes)-1],state,depth+1))
            return "\{\"anyOf\":"+schema_array(alternatives)+"\}"
        }
        for(ft,i in td.argTypes,range(length(td.argTypes))) {
            var inscope parts:array<string>
            var inscope props:array<string>
            var inscope required:array<string>
            props |> push(schema_attr("case","\{\"const\":"+schema_quote(string(td.argNames[i]))+"\}"))
            required |> push(schema_quote("case"))
            if(ft.baseType!=Type.tVoid) {
                props |> push(schema_attr("value",schema_type(ft,state,depth+1)))
                required |> push(schema_quote("value"))
            } else {props |> push(schema_attr("value","false"))}
            parts |> push(schema_attr("type",schema_quote("object")))
            parts |> push(schema_attr("properties",schema_object(props)))
            parts |> push(schema_attr("required",schema_array(required)))
            parts |> push(schema_attr("additionalProperties",state.strict ? "false" : "true"))
            alternatives |> push(schema_object(parts))
        }
        return "\{\"oneOf\":"+schema_array(alternatives)+"\}"
    }
    var low=""
    var high=""
    if(td.baseType==Type.tInt8) {low="-128";high="127"}
    elif(td.baseType==Type.tUInt8) {low="0";high="255"}
    elif(td.baseType==Type.tInt16) {low="-32768";high="32767"}
    elif(td.baseType==Type.tUInt16) {low="0";high="65535"}
    elif(td.baseType==Type.tInt) {low="-2147483648";high="2147483647"}
    elif(td.baseType==Type.tUInt) {low="0";high="4294967295"}
    elif(td.baseType==Type.tInt64) {low="-9223372036854775808";high="9223372036854775807"}
    elif(td.baseType==Type.tUInt64) {low="0";high="9223372036854775807"}
    if(low!="") {return "\{\"type\":\"integer\",\"minimum\":"+low+",\"maximum\":"+high+"\}"}
    if(td.baseType==Type.tFloat || td.baseType==Type.tDouble) {return schema_typed("number")}
    state.error="derive schema: unsupported type {describe(td)}"
    return "false"
}

[call_macro(name="derive_json_schema")]
class DeriveJsonSchema : AstCallMacro {
    def override visit(prog:ProgramPtr;mod:Module?;var expr:ExprCallMacro?) : ExpressionPtr {
        macro_verify(length(expr.arguments)==1 || length(expr.arguments)==2,prog,expr.at,"derive_json_schema expects type<Model> and optional literal strict bool")
        macro_verify(expr.arguments[0] is ExprTypeDecl,prog,expr.at,"derive_json_schema expects a type<T> witness")
        var inscope state:SchemaState
        state.strict=true
        if(length(expr.arguments)==2) {
            macro_verify(expr.arguments[1] is ExprConstBool,prog,expr.at,"derive_json_schema strict must be a bool literal")
            state.strict=(expr.arguments[1] as ExprConstBool).getValue
        }
        let td=(expr.arguments[0] as ExprTypeDecl).typeexpr
        // Wait for type macros such as Option/JsonField to resolve.
        if(td.baseType==Type.typeMacro || td.baseType==Type.alias) {return null}
        let root=schema_type(td,state,0)
        macro_verify(state.error=="",prog,expr.at,state.error)
        var inscope definitions:array<string>
        for(id in state.order) {definitions |> push(schema_attr(id,state.defs[id]))}
        var inscope parts:array<string>
        parts |> push(schema_attr("$schema",schema_quote("https://json-schema.org/draft/2020-12/schema")))
        parts |> push(schema_attr("$defs",schema_object(definitions)))
        parts |> push(schema_attr("allOf","["+root+"]"))
        let text=schema_object(parts)
        return qmacro($v(text))
    }
}
