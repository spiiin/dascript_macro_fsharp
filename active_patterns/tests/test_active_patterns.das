options gen2
require ../recognizers.das
require daslib/match
require daslib/strings_convert

def parity_text(value:int) : string {
    return match (parity(value)) {
        Parity.even => "even"
        Parity.odd => "odd"
    }
}

def parsed_text(text:string) : string {
    return match (text) {
        (integer(_) => found(n)) && n < 0 => "negative {n}"
        (integer(_) => found(n)) => "integer {n}"
        _ => "text"
    }
}

def accepted_level(value, minimum:int) : int {
    return match (value) {
        (at_least(_,minimum) => found(level)) => level
        _ => -999
    }
}

struct Command {argument:string}

def nested(command:Command) : int {
    return match (command) {
        Command(argument=(integer(_) => found(n))) => n
        _ => -999
    }
}

def even_and_ready(value, minimum:int) : bool {
    return match (value) {
        (parity(_) => Parity.even) & (at_least(_,minimum) => found(_)) => true
        _ => false
    }
}

// Standard Result works directly, without RecognizedInt or another adapter.
def standard_result(text:string) : int {
    return match (text) {
        (try_to_int(_) => ok(n)) => n
        _ => -999
    }
}

[export]
def main() {
    verify(parity_text(0)=="even")
    verify(parity_text(1)=="odd" && parity_text(-3)=="odd")
    verify(parity_text(-2)=="even" && parity_text(2147483647)=="odd")
    verify(parsed_text("42")=="integer 42")
    verify(parsed_text("-7")=="negative -7")
    verify(parsed_text("0")=="integer 0")
    verify(parsed_text("")=="text" && parsed_text("oops")=="text")
    verify(parsed_text("12tail")=="text" && parsed_text("2147483648")=="text")
    verify(parsed_text("-2147483648")=="negative -2147483648")
    verify(accepted_level(9,10)==-999)
    verify(accepted_level(10,10)==10 && accepted_level(12,10)==12)
    verify(accepted_level(-3,-4)==-3 && accepted_level(-5,-4)==-999)
    verify(accepted_level(9,8)==9) // Same input, a different pattern parameter.
    verify(nested(Command(argument="42"))==42)
    verify(nested(Command(argument="oops"))==-999)
    verify(even_and_ready(12,10) && !even_and_ready(11,10) && !even_and_ready(8,10))
    verify(standard_result("42")==42 && standard_result("oops")==-999)
    print("Active patterns checks OK\n")
}
