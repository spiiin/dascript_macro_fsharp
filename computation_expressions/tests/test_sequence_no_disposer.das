options gen2
require ../lib/computation.das
[export]
def main() {
 var inscope seq <- computation(SequenceBuilder()) {
  let bad=1 |> use_resource
  yield bad
 }
}
