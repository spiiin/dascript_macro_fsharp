options gen2
module json_provider public
require daslib/ast
require daslib/rtti
require daslib/ast_boost
require daslib/templates_boost
require daslib/fio
require provider_runtime public

// A small teaching format, NOT the JSON Schema standard.
// { "fields": [ { "name": "health", "type": "int" } ] }
[structure_macro(name="json_provider")]
class JsonProvider : AstStructureAnnotation {
    def override apply(var st : StructurePtr; var group : ModuleGroup;
                       args : AnnotationArgumentList; var errors : das_string) : bool {
        let arg = find_arg(args, "schema")
        if (!(arg is tString)) {
            errors := "[json_provider] schema must be a relative file path string"
            return false
        }
        for (a in args) {
            if (a.name != "schema") {
                errors := "[json_provider] unknown annotation argument '{a.name}'"
                return false
            }
        }
        if (length(st.fields) != 0) {
            errors := "[json_provider] annotate an empty struct"
            return false
        }
        let directory = dir_name(string(st.at.fileInfo.name))
        let path = (empty(directory) ? "." : directory) + "/" + (arg as tString)
        let source = fread(path)
        if (empty(source)) {
            errors := "[json_provider] cannot read schema (or empty file): {path}"
            return false
        }
        var error : string
        var schema = read_json(source, error)
        {
            if (schema == null) {
                errors := "[json_provider] {path}: {error}"
                return false
            }
            let fields = schema?["fields"]
            if (!(fields is _array)) {
                errors := "[json_provider] {path}: expected fields array"
                return false
            }

            var statements : array<ExpressionPtr>
            var seen : table<string; bool>
            for (field in fields as _array) {
                let name = field?["name"] ?? ""
                let kind = field?["type"] ?? ""
                // Keep identifiers intentionally narrow in this first example.
                var valid = !empty(name)
                for (c, i in name, range(length(name))) {
                    if (!((c >= 97 && c <= 122) || c == 95 || (i > 0 && c >= 48 && c <= 57))) {
                        valid = false
                    }
                }
                if (!valid || key_exists(seen, name)) {
                    errors := "[json_provider] {path}: invalid or duplicate field '{name}'"
                    return false
                }
                seen[name] = true
                if (kind == "string") {
                    st |> add_structure_field(name, clone_type(qmacro_type(type<string>)), qmacro(""))
                } elif (kind == "int") {
                    st |> add_structure_field(name, clone_type(qmacro_type(type<int>)), qmacro(0))
                } elif (kind == "bool") {
                    st |> add_structure_field(name, clone_type(qmacro_type(type<bool>)), qmacro(false))
                } else {
                    errors := "[json_provider] {path}: field '{name}' has unsupported type '{kind}'"
                    return false
                }
                statements |> push <| qmacro_expr() {
                    if (!provider_read(node, $v(name), value.$f(name), error)) {
                        return false
                    }
                }
            }

            // A real function in the caller's module. No runtime schema lookup.
            var fn = qmacro_function("try_parse_{st.name}") $(text : string; var result : $t(st); var error : string&) : bool {
                error = ""
                var node = read_json(text, error)
                {
                    if (node == null) { return false }
                    if (!(node is _object)) {
                        error = "expected JSON object"
                        return false
                    }
                    var value = default<$t(st)>
                    $b(statements)
                    result = value
                    return true
                } finally { delete_json(node) }
            }
            fn.flags.generated = true
            fn.body |> force_at(st.at)
            add_function(st._module, fn)
            print("[json_provider] {st.name}: {length(st.fields)} fields from {path}\n")
            return true
        } finally { delete_json(schema) }
    }
}
