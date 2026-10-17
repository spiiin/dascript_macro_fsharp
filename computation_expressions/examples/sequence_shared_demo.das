options gen2
require ../lib/computation.das
var cleaned_health=0
struct EnemyState {health:int;hits:int}
[export]
def main() {
 var inscope health <- computation(SequenceBuilder()) {
  var enemy=EnemyState(health=100,hits=0)
  try_finally($ {
   enemy.health-=25
   enemy.hits++
   yield enemy.health
   enemy.health-=10
   enemy.hits++
  }, $ {
   cleaned_health=enemy.health
   print("cleanup: health={enemy.health}, hits={enemy.hits}\n")
   enemy.health+=5
  })
  // Sees changes from both the protected body and cleanup.
  yield enemy.health
 }
 var i=0
 for(value in health) {
  print("health={value}\n")
  assert(value==(i==0 ? 75 : 70))
  i++
 }
 assert(cleaned_health==65 && i==2)
 print("sequence shared capture demo OK\n")
}
