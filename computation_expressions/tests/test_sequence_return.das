options gen2
require ../lib/computation.das
[export]
def main() {
 var inscope seq <- computation(SequenceBuilder()) { return 1 }
}
