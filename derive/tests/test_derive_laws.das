options gen2
require ../lib/derive.das
[derive]
struct Key {group:int;code:int}
[derive]
struct RealKey {value:float}
[export]
def main() {
    let keys=fixed_array(Key(group=0,code=0),Key(group=0,code=1),Key(group=0,code=0),Key(group=1,code=0),Key(group=-1,code=3))
    for(a in keys) {
        verify(derive_equal(a,a))
        for(b in keys) {
            verify(derive_equal(a,b)==derive_equal(b,a))
            if(derive_equal(a,b)) {verify(derive_hash(a)==derive_hash(b))}
            for(c in keys) {
                if(derive_equal(a,b) && derive_equal(b,c)) {verify(derive_equal(a,c))}
            }
        }
    }
    let realKeys=fixed_array(RealKey(value=0.0),RealKey(value=-0.0),RealKey(value=1.5),RealKey(value=-2.0),RealKey(value=1.5))
    for(a in realKeys) {
        for(b in realKeys) {
            if(derive_equal(a,b)) {verify(derive_hash(a)==derive_hash(b))}
        }
    }
    let nan=unsafe(reinterpret<float>(0x7fc00000u))
    verify(!derive_equal(nan,nan))
    verify(!derive_equal(RealKey(value=nan),RealKey(value=nan)))
    print("Derive composition laws OK\n")
}
