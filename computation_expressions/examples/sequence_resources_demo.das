options gen2
require ../support/json_resource_example.das
require daslib/rtti
var journal=""
def document(text:string) : JsonResource {
 let parsed=open_document(text)
 if(parsed is err) {panic(parsed as err)}
 return parsed as ok
}
def enemy_health(fail:bool) {
 return <- computation(SequenceBuilder()) {
  let data=document("\{\"health\":42\}") |> use_resource
  try_finally($ {
   yield int(data.node?["health"] as _longint)
   if(fail) {panic("enemy update failed")}
   yield 43
  }, $ {journal+="scope closed; "; print("scope closed\n")})
 }
}
[export]
def main() {
 {
  var inscope health <- enemy_health(false)
  assert(resource_opens==0)
  for(value in health) {print("first health: {value}\n"); break}
  assert(resource_opens==1 && resource_closes==1)
 }
 {
  var inscope health <- enemy_health(false)
  for(value in health) {print("health: {value}\n")}
  assert(resource_closes==2)
 }
 {
  var inscope health <- enemy_health(true)
  try {for(value in health) {print("before error: {value}\n")}} recover {
   print("caught: {this_context().last_exception}\n")
  }
  assert(resource_closes==3)
 }
 {
  var inscope health <- enemy_health(false)
  try {sequence_each(health, $(value:int) {panic("consumer failed")})} recover {
   print("caught consumer error\n")
  }
  assert(resource_closes==4)
 }
 print("sequence resources demo OK\n")
}
