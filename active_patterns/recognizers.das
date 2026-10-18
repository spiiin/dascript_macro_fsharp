options gen2
module recognizers public
require daslib/strings_convert

// These are ordinary functions. Standard daslib/match supplies view patterns.
enum Parity {
    even
    odd
}

def parity(value:int) : Parity {
    return value % 2 == 0 ? Parity.even : Parity.odd
}

variant RecognizedInt {
    found:int
    missing:bool
}

def integer(text:string) : RecognizedInt {
    let parsed=try_to_int(text)
    return is_ok(parsed) ? RecognizedInt(found=unwrap(parsed)) : RecognizedInt(missing=true)
}

def at_least(value, minimum:int) : RecognizedInt {
    return value >= minimum ? RecognizedInt(found=value) : RecognizedInt(missing=true)
}
