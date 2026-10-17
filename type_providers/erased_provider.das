options gen2
module erased_provider public
require daslib/ast
require daslib/ast_boost
require daslib/templates_boost
require daslib/fio
require erased_runtime public

// These descriptors belong to the macro, NOT to the user's runtime data model.
struct EpField {
    name : string
    kind : string
    target : string
}

struct EpSchema {
    path : string
    fields : array<EpField>
}

def ep_type_name(name : string) : bool {
    if (empty(name)) { return false }
    for (c, i in name, range(length(name))) {
        if (!((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
                || (i > 0 && c >= 48 && c <= 57))) { return false }
    }
    return true
}

// No directory scan and no recursive reference resolution. One file per type.
// Cache lifetime is the macro instance used for this compilation.
def ep_load(var cache : array<EpSchema>; path : string; var error : string&) : int {
    for (schema, index in cache, range(length(cache))) {
        if (schema.path == path) { return index }
    }
    let source = fread(path)
    if (empty(source)) {
        error = "cannot read schema (or empty file): {path}"
        return -1
    }
    var node = read_json(source, error)
    {
        if (node == null) {
            error = "{path}: {error}"
            return -1
        }
        let list = node?["fields"]
        if (!(list is _array)) {
            error = "{path}: expected fields array"
            return -1
        }
        var schema = EpSchema(path=path)
        var seen : table<string; bool>
        for (entry in list as _array) {
            let name = entry?["name"] ?? ""
            if (!ep_type_name(name) || key_exists(seen, name)) {
                error = "{path}: invalid or duplicate field '{name}'"
                return -1
            }
            seen[name] = true
            // Do not resolve 'target' here: that would eagerly walk the graph.
            schema.fields |> push(EpField(name=name,
                kind=entry?["type"] ?? "", target=entry?["target"] ?? ""))
        }
        cache |> emplace(schema)
        print("[erased.load] {path}\n")
        return length(cache) - 1
    } finally { delete_json(node) }
}

// A tiny expression DSL:
// erased(json, "catalog", "Player", _.team.leader.name)
// Virtual types are checked here and completely absent from the emitted AST.
[call_macro(name="erased")]
class ErasedProvider : AstCallMacro {
    cache : array<EpSchema>

    def override canVisitArgument(expr : ExprCallMacro?; index : int) : bool {
        // '_' and virtual members are intentionally NOT inferred by daslang.
        return index < 3
    }

    def override canFoldReturnResult(expr : ExprCallMacro?) : bool {
        return false
    }

    def override visit(prog : ProgramPtr; mod : Module?; var expr : ExprCallMacro?) : ExpressionPtr {
        if (length(expr.arguments) != 4) {
            macro_error(prog, expr.at, "erased expects (json, catalog, root_type, _.field.path)")
            return null
        }
        if (!(expr.arguments[1] is ExprConstString) || !(expr.arguments[2] is ExprConstString)) {
            macro_error(prog, expr.at, "erased: catalog and root_type must be string literals")
            return null
        }
        let catalog = string((expr.arguments[1] as ExprConstString).value)
        var current = string((expr.arguments[2] as ExprConstString).value)
        if (!ep_type_name(current)) {
            macro_error(prog, expr.at, "erased: invalid root type name '{current}'")
            return null
        }
        let directory = dir_name(string(expr.at.fileInfo.name))
        let base = (empty(directory) ? "." : directory) + "/" + catalog

        // Extract a path from ordinary field-access AST, in reverse order.
        var members : array<string>
        var cursor = clone_expression(expr.arguments[3])
        while (cursor is ExprField) {
            members |> push(string((cursor as ExprField).name))
            cursor = clone_expression((cursor as ExprField).value)
        }
        if (!(cursor is ExprVar) || empty(members)) {
            macro_error(prog, expr.at, "erased: selector must be a nonempty path such as _.team.name")
            return null
        }
        if ((cursor as ExprVar).name != "_") {
            macro_error(prog, expr.at, "erased: selector must start with '_'")
            return null
        }

        var emitted = qmacro(ep_root($e(expr.arguments[0])))
        var full_path = current
        for (step in range(length(members))) {
            let member = members[length(members) - step - 1]
            let file = base + "/" + current + ".json"
            var error : string
            let index = ep_load(cache, file, error)
            if (index < 0) {
                macro_error(prog, expr.at, "erased: {error}")
                return null
            }
            var found = false
            var field = EpField()
            for (candidate in cache[index].fields) {
                if (candidate.name == member) {
                    field = candidate
                    found = true
                    break
                }
            }
            if (!found) {
                macro_error(prog, expr.at, "erased: type '{current}' has no field '{member}' ({file})")
                return null
            }
            full_path += "." + member
            let leaf = step == length(members) - 1
            if (field.kind == "ref") {
                if (!ep_type_name(field.target)) {
                    macro_error(prog, expr.at, "erased: {full_path}: invalid ref target '{field.target}'")
                    return null
                }
                emitted = qmacro(ep_object($e(emitted), $v(member), $v(full_path)))
                current = field.target
                // Even at the end of a ref selector, do not load target schema.
            } else {
                if (!leaf) {
                    macro_error(prog, expr.at, "erased: cannot navigate through scalar '{full_path}'")
                    return null
                }
                if (field.kind == "string") {
                    emitted = qmacro(ep_string($e(emitted), $v(member), $v(full_path)))
                } elif (field.kind == "int") {
                    emitted = qmacro(ep_int($e(emitted), $v(member), $v(full_path)))
                } elif (field.kind == "bool") {
                    emitted = qmacro(ep_bool($e(emitted), $v(member), $v(full_path)))
                } else {
                    macro_error(prog, expr.at, "erased: {full_path}: unsupported type '{field.kind}'")
                    return null
                }
            }
        }
        // Only the original JSON expression and selected key literals survive.
        emitted |> force_at(expr.at)
        return emitted
    }
}
