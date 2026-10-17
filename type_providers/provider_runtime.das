options gen2
module provider_runtime public
require daslib/json_boost public

// Runtime helpers: the macro generates calls with statically typed destinations.
def provider_read(node : JsonValue?; key : string; var dst : string&; var error : string&) : bool {
    let v = node?[key]
    if (!(v is _string)) {
        error = "field '{key}': expected string"
        return false
    }
    dst = v as _string
    return true
}

def provider_read(node : JsonValue?; key : string; var dst : int&; var error : string&) : bool {
    let v = node?[key]
    if (!(v is _longint)) {
        error = "field '{key}': expected integer"
        return false
    }
    let n = v as _longint
    if (n < -2147483648l || n > 2147483647l) {
        error = "field '{key}': integer outside int32 range"
        return false
    }
    dst = int(n)
    return true
}

def provider_read(node : JsonValue?; key : string; var dst : bool&; var error : string&) : bool {
    let v = node?[key]
    if (!(v is _bool)) {
        error = "field '{key}': expected boolean"
        return false
    }
    dst = v as _bool
    return true
}
