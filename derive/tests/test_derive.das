options gen2
require ../lib/derive.das
require daslib/rtti

enum Team {
    red
    blue
}
[derive]
struct Stats {health:int;mana:int}
[derive]
struct Player {name:string;active:bool;team:Team;stats:Stats}
[derive]
struct Empty {}
[derive]
struct Measurements {height:float;weight:double;samples:float[3]}
[derive(debug=true,equality=false,hash=false)]
struct DebugOnly {value:int}
[derive(debug=false)]
struct Identity {id:int}

struct EntityId {raw:int}
def derive_equal(a,b:EntityId) : bool {return a.raw%10==b.raw%10}
def derive_hash(value:EntityId) : uint64 {return derive_hash(value.raw%10)}
def derive_debug(value:EntityId) : string {return "id#{value.raw%10}"}
[derive]
struct Entity {id:EntityId;name:string}

def check() {
    let a=Player(name="Alice",active=true,team=Team.red,stats=Stats(health=100,mana=25))
    var b=a
    verify(derive_equal(a,b))
    verify(derive_hash(a)==derive_hash(b))
    verify(derive_debug(a)=="Player\{name=\"Alice\", active=true, team={Team.red}, stats=Stats\{health=100, mana=25\}\}")
    b.stats.health=75
    verify(!derive_equal(a,b) && !derive_equal(b,a))
    b=a;b.name="Bob";verify(!derive_equal(a,b))
    b=a;b.active=false;verify(!derive_equal(a,b))
    b=a;b.team=Team.blue;verify(!derive_equal(a,b))
    verify(derive_equal(Empty(),Empty()) && derive_debug(Empty())=="Empty\{\}")
    verify(derive_hash(Empty())==derive_hash(Empty()))
    verify(derive_debug(DebugOnly(value=4))=="DebugOnly\{value=4\}")
    verify(derive_equal(Identity(id=4),Identity(id=4)))
    verify(derive_hash(Identity(id=4))==derive_hash(Identity(id=4)))
    verify(derive_debug("a\"b\\c\n\t") == "\"a\\\"b\\\\c\\n\\t\"")
    verify(derive_debug(false)=="false")
    verify(derive_hash(uint64(0))==0xe220a8397b1dcdaful)
    verify(derive_equal(int8(-1),int8(-1)) && derive_equal(uint64(15),uint64(15)))
    verify(derive_hash(+0.0)==derive_hash(-0.0) && derive_equal(+0.0,-0.0))
    verify(derive_hash(double(+0.0))==derive_hash(double(-0.0)))
    let negativeZero=unsafe(reinterpret<float>(0x80000000u))
    verify(derive_equal(negativeZero,0.0) && derive_hash(negativeZero)==derive_hash(0.0))
    let m=Measurements(height=0.0,weight=double(0),samples=fixed_array(1.0,0.0,2.0))
    let n=Measurements(height=-0.0,weight=-double(0),samples=fixed_array(1.0,-0.0,2.0))
    verify(derive_equal(m,n) && derive_hash(m)==derive_hash(n))
    var nullText:string
    verify(derive_debug(nullText)=="\"\"")
    verify(derive_equal(nullText,""))
    verify(derive_hash(nullText)==derive_hash(""))
    let e=Entity(id=EntityId(raw=11),name="same")
    let f=Entity(id=EntityId(raw=21),name="same")
    verify(derive_equal(e,f) && derive_hash(e)==derive_hash(f))
    verify(derive_debug(e)=="Entity\{id=id#1, name=\"same\"\}")
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive checks OK\n")
}
