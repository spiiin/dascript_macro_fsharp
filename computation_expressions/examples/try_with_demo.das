options gen2
require ../lib/computation.das
[export]
def main() {
 let safe=computation(ResultBuilder()) {
  try_with($ {
   panic("configuration unavailable")
   return 0
  }, $(message:string) {
   print("using default after: {message}\n")
   return 100
  })
 }
 assert(safe is ok && (safe as ok)==100)
 var inscope health <- computation(SequenceBuilder()) {
  var current=100
  try_with($ {
   try_finally($ {
    current-=10
    yield current
    current-=20
    panic("connection lost")
   }, $ {print("connection scope closed; health={current}\n")})
  }, $(message:string) {
   print("recovery: {message}\n")
   yield current
   current+=5
   yield current
  })
  yield current+1
 }
 let expected=[90,70,75,76]
 var i=0
 for(value in health) {
  assert(value==expected[i]);i++
  print("health={value}\n")
 }
 assert(i==4)
 print("try_with demo OK\n")
}
