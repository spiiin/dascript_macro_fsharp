options gen2
require ../lib/computation.das
require daslib/rtti
require daslib/strings_boost
var log=""
struct Game {health:int;score:int}
struct Resource {id:int}
def acquire(id:int) {return Resource(id=id)}
def ce_dispose(var r:Resource) {log+="dispose:{r.id};"}
def shared_game(fail:bool) {
 return <- computation(SequenceBuilder()) {
  var game=Game(health=10,score=0)
  try_finally($ {
   let resource=acquire(7) |> use_resource
   game.health-=3
   game.score+=5
   yield game.health
   if(fail) {panic("failed update")}
   game.score+=2
  }, $ {log+="game:{game.health},{game.score};"; game.health+=1})
  yield game.health
 }
}
[export]
def main() {
 {
  var inscope seq <- shared_game(false)
  var index=0
  for(v in seq) {assert(v==7+index);index++}
  assert(index==2 && log=="dispose:7;game:7,7;")
 }
 log=""
 {
  var inscope seq <- shared_game(false)
  for(v in seq) {assert(v==7);break}
  assert(log=="dispose:7;game:7,5;")
 }
 log=""
 {
  var inscope seq <- shared_game(true)
  var caught=false
  try {for(v in seq) {}} recover {
   caught=true
   assert(this_context().last_exception |> contains("failed update"))
  }
  assert(caught && log=="dispose:7;game:7,5;")
 }
 log=""
 {
  var inscope seq <- computation(SequenceBuilder()) {
   var x=1
   try_finally($ {
    var x=10
    try_finally($ {x++;yield x}, $ {log+="inner:{x};"})
    yield x
   }, $ {log+="outer:{x};";x+=2})
   yield x
  }
  let expected=[11,11,3]
  var i=0
  for(v in seq) {assert(v==expected[i]);i++}
  assert(i==3 && log=="inner:11;outer:1;")
 }
 log=""
 {
  var inscope seq <- computation(SequenceBuilder()) {
   var n=[1,2] |> bind
   try_finally($ {n+=10;yield n}, $ {log+="{n};";n++})
   yield n
  }
  let expected=[11,12,12,13]
  var i=0
  for(v in seq) {assert(v==expected[i]);i++}
  assert(i==4 && log=="11;12;")
 }
 log=""
 {
  var inscope seq <- computation(SequenceBuilder()) {
   var x=3
   try_finally($ {
    for(x in range(x)) {yield x}
    yield invoke($(x:int) {return x+1},9)
    var x=x+1
    yield x
   }, $ {log+="{x};"})
   try_finally($ {let x=20;yield x}, $ {log+="{x};"})
   yield x
  }
  let expected=[0,1,2,10,4,20,3]
  var i=0
  for(v in seq) {assert(v==expected[i]);i++}
  assert(i==7 && log=="3;3;")
 }
 log=""
 {
  var inscope seq <- computation(SequenceBuilder()) {
   var n:int
   var a,b:int
   a=1
   b=2
   try_finally($ {n=a+b;yield n}, $ {n++})
   yield n
  }
  var i=0
  for(v in seq) {assert(v==3+i);i++}
  assert(i==2)
 }
 print("sequence shared capture checks OK\n")
}

