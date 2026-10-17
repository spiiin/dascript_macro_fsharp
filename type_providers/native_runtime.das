options gen2
module native_runtime public
require provider_runtime public
require daslib/apply public

// Compile-time specialization of this generic unrolls field access.
// No schema files, JSON pointers or descriptors are retained in the result.
def native_decode(node : JsonValue?; var value : auto(T); var error : string&; path : string) : bool {
    if (!(node is _object)) {
        error = "{path}: expected object"
        return false
    }
    var ok = true
    apply_imm(value) $(name : string; var field) {
        if (ok) {
            static_if (typeinfo is_struct(field)) {
                ok = native_decode(node?[name], field, error, path + "." + name)
            } else {
                ok = provider_read(node, name, field, error)
                if (!ok) { error = path + "." + name + ": " + error }
            }
        }
    }
    return ok
}

def try_load_native(text : string; var result : auto(T); var error : string&) : bool {
    error = ""
    var node = read_json(text, error)
    {
        if (node == null) { return false }
        var value = default<T>
        if (!native_decode(node, value, error, "$")) { return false }
        result = value
        return true
    } finally { delete_json(node) }
}
