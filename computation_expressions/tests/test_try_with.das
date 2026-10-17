options gen2
require ../lib/computation.das
require daslib/rtti
require daslib/strings_boost
var handlers=0
var trace=""
struct Handle {id:int}
def ce_dispose(var h:Handle) {trace+="close{h.id};"}
[export]
def main() {
 let ok=computation(ResultBuilder()) {
  try_with($ {return 7}, $(message:string) {handlers++;return 9})
 }
 assert(ok is ok && (ok as ok)==7 && handlers==0)
 let recovered=computation(ResultBuilder()) {
  try_with($ {
   let h=Handle(id=1) |> use_resource
   panic("native error")
   return 0
  }, $(message:string) {
   assert(message |> contains("native error"))
   assert(trace=="close1;")
   handlers++
   return 42
  })
 }
 assert(recovered is ok && (recovered as ok)==42 && handlers==1)
 let error=computation(ResultBuilder()) {
  try_with($ {return result_error("value",type<int>) |> return_from}, $(message:string) {handlers++;return 0})
 }
 assert(error is error && handlers==1)
 let absent=computation(OptionBuilder()) {
  try_with($ {return none(type<int>) |> return_from}, $(message:string) {handlers++;return 0})
 }
 assert(absent is none && handlers==1)
 let option=computation(OptionBuilder()) {
  try_with($ {panic("option");return 0}, $(message:string) {return 8})
 }
 assert(option is some && (option as some)==8)
 let state=computation(StateBuilder(1)) {
  try_with($ {state_put(5) |> bind;panic("state");return 0}, $(message:string) {
   let value=state_get() |> bind
   return value
  })
 }
 assert(state.value==5 && state.state==5)
 let sr=computation(StateResultBuilder(1)) {
  try_with($ {state_put(5) |> bind;panic("state-result");return 0}, $(message:string) {
   return result_error("rollback",type<int>) |> return_from
  })
 }
 assert(sr.result is error && sr.state==1)
 let writer=computation(WriterBuilder()) {
  try_with($ {tell("lost;") |> bind;panic("writer");return 0}, $(message:string) {
   tell("recovered;") |> bind
   return 9
  })
 }
 assert(writer.value==9 && writer.log=="recovered;")
 let wr=computation(WriterResultBuilder()) {
  try_with($ {panic("writer-result");return 0}, $(message:string) {
   tell("handler;") |> bind
   return 10
  })
 }
 assert(wr.result is ok && (wr.result as ok)==10 && wr.log=="handler;")
 var inscope list <- computation(ListBuilder()) {
  try_with($ {yield 1;panic("list");yield 2}, $(message:string) {yield 8;yield 9})
  yield 10
 }
 assert(length(list)==3 && list[0]==8 && list[1]==9 && list[2]==10)
 var after=0
 let unit=computation(ResultBuilder()) {
  try_with($ {panic("unit")}, $(message:string) {after++})
  after++
  return after
 }
 assert((unit as ok)==2)
 var caught=false
 try {
  let result=computation(ResultBuilder()) {
   try_with($ {panic("first");return 0}, $(message:string) {handlers++;panic("second");return 0})
  }
 } recover {caught=true;assert(this_context().last_exception |> contains("second"))}
 assert(caught && handlers==2)
 print("try_with eager checks OK\n")
}
