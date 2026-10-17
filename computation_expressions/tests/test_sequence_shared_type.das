options gen2
require ../lib/computation.das
[export]
def main() {
 var inscope seq <- computation(SequenceBuilder()) {
  var x:int="wrong"
  try_finally($ {yield x}, $ {})
 }
}
