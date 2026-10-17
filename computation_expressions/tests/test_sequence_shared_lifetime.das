options gen2
require ../lib/computation.das
[export]
def main() {
 let baseline=heap_bytes_allocated()
 var peak0=0ul
 var peak1=0ul
 {
  var inscope seq <- computation(SequenceBuilder()) {
   for(i in range(1000)) {
    var n=i
    try_finally($ {n++; yield n}, $ {n++})
   }
  }
  for(v in seq) {
   if(v==1) {peak0=heap_bytes_allocated()}
   if(v==1000) {peak1=heap_bytes_allocated()}
  }
 }
 let after=heap_bytes_allocated()
 assert(peak0==peak1 && after==baseline)
 print("sequence cell lifetime checks OK\n")
}

