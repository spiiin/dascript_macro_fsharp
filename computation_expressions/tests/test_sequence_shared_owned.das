options gen2
require ../lib/computation.das
[export]
def main() {
 var inscope seq <- computation(SequenceBuilder()) {
  var inscope x:array<int>
  try_finally($ {yield length(x)}, $ {})
 }
}
