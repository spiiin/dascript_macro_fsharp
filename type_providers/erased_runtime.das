options gen2
module erased_runtime public
require provider_runtime public

// All virtual object types erase to the same borrowed JsonValue? pointer.
// The owner must keep the root JSON tree alive while using these views.
def ep_root(var node : JsonValue?) : JsonValue? {
    if (!(node is _object)) { panic("erased: root must be a JSON object") }
    return node
}

def ep_object(var node : JsonValue?; key, location : string) : JsonValue? {
    var child = node?[key]
    if (!(child is _object)) { panic("erased: {location}: expected object") }
    return child
}

def ep_string(node : JsonValue?; key, location : string) : string {
    var result : string
    var error : string
    if (!provider_read(node, key, result, error)) { panic("erased: {location}: {error}") }
    return result
}

def ep_int(node : JsonValue?; key, location : string) : int {
    var result : int
    var error : string
    if (!provider_read(node, key, result, error)) { panic("erased: {location}: {error}") }
    return result
}

def ep_bool(node : JsonValue?; key, location : string) : bool {
    var result : bool
    var error : string
    if (!provider_read(node, key, result, error)) { panic("erased: {location}: {error}") }
    return result
}
