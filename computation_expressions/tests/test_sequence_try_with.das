options gen2
require ../lib/computation.das
require daslib/rtti
require daslib/strings_boost
var trace=""
var handlers=0
struct Handle {id:int}
def ce_dispose(var h:Handle) {trace+="close{h.id};"}
def values(fail:bool) {
 return <- computation(SequenceBuilder()) {
  var n=1
  try_with($ {
   let h=Handle(id=1) |> use_resource
   yield n
   n=2
   if(fail) {panic("producer")}
   yield n
  }, $(message:string) {
   assert(message |> contains("producer"))
   assert(trace=="close1;")
   handlers++
   let h=Handle(id=2) |> use_resource
   yield n+10
   yield n+20
  })
  yield n+30
 }
}
[export]
def main() {
 {
  var inscope seq <- values(true)
  assert(handlers==0 && trace=="")
  let expected=[1,12,22,32]
  var i=0
  for(v in seq) {assert(v==expected[i]);i++}
  assert(i==4 && handlers==1 && trace=="close1;close2;")
 }
 trace="";handlers=0
 {
  var inscope seq <- values(false)
  let expected=[1,2,32]
  var i=0
  for(v in seq) {assert(v==expected[i]);i++}
  assert(i==3 && handlers==0 && trace=="close1;")
 }
 trace="";handlers=0
 {
  var inscope seq <- values(true)
  for(v in seq) {break}
  assert(handlers==0 && trace=="close1;")
 }
 trace="";handlers=0
 {
  var inscope seq <- values(true)
  for(v in seq) {if(v==12) {break}}
  assert(handlers==1 && trace=="close1;close2;")
 }
 trace="";handlers=0
 {
  var inscope seq <- computation(SequenceBuilder()) {
   try_with($ {panic("body");yield 0}, $(message:string) {
    handlers++
    let h=Handle(id=3) |> use_resource
    yield 1
    panic("handler")
   })
  }
  var caught=false
  try {for(v in seq) {assert(v==1)}} recover {
   caught=true
   assert(this_context().last_exception |> contains("handler"))
  }
  assert(caught && handlers==1 && trace=="close3;")
 }
 handlers=0
 {
  var inscope seq <- computation(SequenceBuilder()) {
   try_with($ {
    try_with($ {panic("body");yield 0}, $(message:string) {handlers++;panic("fallback");yield 0})
   }, $(message:string) {handlers++;yield 99})
  }
  for(v in seq) {assert(v==99)}
  assert(handlers==2)
 }
 handlers=0
 {
  var inscope seq <- computation(SequenceBuilder()) {
   try_with($ {
    try_finally($ {yield 1}, $ {panic("cleanup")})
   }, $(message:string) {assert(message |> contains("cleanup"));handlers++;yield 2})
  }
  var sum=0
  for(v in seq) {sum+=v}
  assert(sum==3 && handlers==1)
 }
 handlers=0
 {
  var inscope seq <- computation(SequenceBuilder()) {
   try_with($ {panic("empty");yield 0}, $(message:string) {handlers++})
   yield 7
  }
  var count=0
  for(v in seq) {assert(v==7);count++}
  assert(count==1 && handlers==1)
 }
 handlers=0
 {
  var inscope seq <- computation(SequenceBuilder()) {
   for(i in range(3)) {
    try_with($ {panic("iteration");yield 0}, $(message:string) {handlers++;yield i})
   }
  }
  var sum=0
  for(v in seq) {sum+=v}
  assert(sum==3 && handlers==3)
 }
 trace="";handlers=0
 {
  var inscope seq <- values(true)
  var caught=false
  try {sequence_each(seq, $(v:int) {panic("consumer")})} recover {caught=true}
  assert(caught && handlers==0 && trace=="close1;")
 }
 print("try_with sequence checks OK\n")
}

