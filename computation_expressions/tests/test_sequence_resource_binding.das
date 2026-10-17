options gen2
require ../lib/computation.das
[export]
def main() {
 var inscope seq <- computation(SequenceBuilder()) {
  1 |> use_resource
  yield 1
 }
}
