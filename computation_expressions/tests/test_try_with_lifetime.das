options gen2
require ../lib/computation.das
[export]
def main() {
 let before=heap_bytes_allocated()
 for(i in range(100)) {
  var inscope seq <- computation(SequenceBuilder()) {
   try_with($ {yield 1;panic("expected")}, $(message:string) {yield 2})
  }
  for(v in seq) {}
 }
 let after=heap_bytes_allocated()
 print("heap {before} {after}\n")
 assert(before==after)
 print("try_with lifetime checks OK\n")
}
