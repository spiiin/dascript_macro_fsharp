options gen2
require ../lib/derive.das
[derive]
struct Stats {health:int;mana:int}
[derive]
struct Player {name:string;stats:Stats}
[export]
def main() {
    let a=Player(name="Alice",stats=Stats(health=100,mana=25))
    let b=Player(name="Alice",stats=Stats(health=100,mana=25))
    print("{derive_debug(a)}\n")
    verify(derive_equal(a,b) && derive_hash(a)==derive_hash(b))
    print("Derive demo OK\n")
}
