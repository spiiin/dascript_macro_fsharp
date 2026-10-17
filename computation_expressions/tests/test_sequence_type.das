options gen2
require ../lib/computation.das
[export]
def main() {
 var inscope seq <- computation(SequenceBuilder()) { yield "wrong" }
 for (value in seq) { print("{value}") }
}
