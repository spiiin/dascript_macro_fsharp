options gen2
require ../recognizers.das
require daslib/match

[export]
def main() {
    // Total recognizer: one classification, exhaustive enum match.
    let value=12
    let kind=match (parity(value)) {
        Parity.even => "even"
        Parity.odd => "odd"
    }
    print("Total: {value} is {kind}\n")

    // Partial recognizer: failure falls through, success extracts a payload.
    for(text in ["42", "-7", "hello"]) {
        let description=match (text) {
            (integer(_) => found(n)) && n < 0 => "negative {n}"
            (integer(_) => found(n)) => "integer {n}"
            _ => "text"
        }
        print("Partial: {text} -> {description}\n")
    }

    // Parameterized recognizer: minimum is supplied by the caller.
    let minimum=10
    let eligibility=match (value) {
        (at_least(_,minimum) => found(level)) => "accepted level {level}"
        _ => "level is too low"
    }
    print("Parameterized: {eligibility}\n")

    // Views compose with ordinary structural patterns and with each other.
    let ready=match (value) {
        (parity(_) => Parity.even) & (at_least(_,minimum) => found(_)) => true
        _ => false
    }
    verify(kind=="even" && ready)
    print("Active patterns demo OK\n")
}
