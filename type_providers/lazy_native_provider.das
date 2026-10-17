options gen2
module lazy_native_provider public
require daslib/ast
require daslib/ast_boost
require daslib/templates_boost
require daslib/fio
require native_runtime public

def native_identifier(name : string) : bool {
    if (empty(name)) { return false }
    for (c, i in name, range(length(name))) {
        if (!((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
                || (i > 0 && c >= 48 && c <= 57))) { return false }
    }
    return true
}

def generate_native(prog : ProgramPtr; mod : Module?; catalog, name : string;
                    at : LineInfo; var active : array<string>) : TypeDeclPtr {
    if (!native_identifier(name)) {
        macro_error(prog, at, "provided_type: invalid type name '{name}'")
        return null
    }
    let file = catalog + "/" + name + ".json"
    let identity = "Provided<{file}>"
    for (ancestor in active) {
        if (ancestor == identity) {
            macro_error(prog, at, "provided_type: by-value dependency cycle at '{name}'; use an ID to break the cycle")
            return null
        }
    }
    var existing = prog.find_unique_structure(identity)
    if (existing != null) {
        return new TypeDecl(baseType=Type.tStructure, structType=existing, at=at)
    }
    let source = fread(file)
    if (empty(source)) {
        macro_error(prog, at, "provided_type: cannot read dependency '{file}'")
        return null
    }
    var error : string
    var schema = read_json(source, error)
    active |> push(identity)
    {
        if (schema == null) {
            macro_error(prog, at, "provided_type: {file}: {error}")
            return null
        }
        let fields = schema?["fields"]
        if (!(fields is _array)) {
            macro_error(prog, at, "provided_type: {file}: expected fields array")
            return null
        }
        var st = new Structure(name := identity, at=at)
        var seen : table<string; bool>
        for (field in fields as _array) {
            let fname = field?["name"] ?? ""
            let kind = field?["type"] ?? ""
            if (!native_identifier(fname) || key_exists(seen, fname)) {
                macro_error(prog, at, "provided_type: {file}: invalid or duplicate field '{fname}'")
                return null
            }
            seen[fname] = true
            var ft : TypeDeclPtr
            if (kind == "string") {
                ft = clone_type(qmacro_type(type<string>))
            } elif (kind == "int") {
                ft = clone_type(qmacro_type(type<int>))
            } elif (kind == "bool") {
                ft = clone_type(qmacro_type(type<bool>))
            } elif (kind == "ref") {
                ft = generate_native(prog, mod, catalog, field?["target"] ?? "", at, active)
                if (ft == null) { return null }
            } else {
                macro_error(prog, at, "provided_type: {file}: unsupported type '{kind}' for '{fname}'")
                return null
            }
            st |> add_structure_field(fname, ft, qmacro(default<$t(ft)>))
        }
        add_structure(mod, st)
        print("[native.generate] {name} from {file}\n")
        return new TypeDecl(baseType=Type.tStructure, structType=st, at=at)
    } finally {
        active |> pop
        delete_json(schema)
    }
}

[type_macro(name="provided_type")]
class NativeTypeProvider : AstTypeMacro {
    def override visit(prog : ProgramPtr; mod : Module?; td, passT : TypeDeclPtr) : TypeDeclPtr {
        if (length(td.typeMacroExpr) != 3) {
            macro_error(prog, td.at, "provided_type expects (catalog, type_name)")
            return null
        }
        if (!(td.typeMacroExpr[1] is ExprConstString) || !(td.typeMacroExpr[2] is ExprConstString)) {
            macro_error(prog, td.at, "provided_type requires two string literals")
            return null
        }
        let relative = string((td.typeMacroExpr[1] as ExprConstString).value)
        let name = string((td.typeMacroExpr[2] as ExprConstString).value)
        let directory = dir_name(string(td.at.fileInfo.name))
        let catalog = get_full_file_name((empty(directory) ? "." : directory) + "/" + relative)
        var inscope active : array<string>
        return generate_native(prog, mod, catalog, name, td.at, active)
    }
}
