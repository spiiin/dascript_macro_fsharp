options gen2
require ../lib/computation.das
[export]
def main() {
 var inscope values <- computation(ListBuilder()) {
  yield 1
  [2,3] |> yield_from
  for(i in range(2)) { yield i+4 }
  yield 6
 }
 assert(length(values)==6)
 for(i in range(6)) { assert(values[i]==i+1) }
 print("list yield checks OK\n")
}
