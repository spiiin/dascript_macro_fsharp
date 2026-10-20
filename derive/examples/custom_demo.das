options gen2
require ../lib/derive.das
// The logical identity ignores the generation digit. All three hooks agree.
struct EntityId {raw:int}
def derive_equal(a,b:EntityId) : bool {return a.raw%100==b.raw%100}
def derive_hash(value:EntityId) : uint64 {return derive_hash(value.raw%100)}
def derive_debug(value:EntityId) : string {return "EntityId({value.raw%100})"}
[derive]
struct Target {id:EntityId;title:string}
// Named functions only: this does not install an implicit == or hash override.
[derive(debug=false)]
struct CacheKey {scene:int;entity:int}
[export]
def main() {
    let first=Target(id=EntityId(raw=107),title="door")
    let second=Target(id=EntityId(raw=207),title="door")
    verify(derive_equal(first,second))
    verify(derive_hash(first)==derive_hash(second))
    verify(derive_debug(first)=="Target\{id=EntityId(7), title=\"door\"\}")
    print("{derive_debug(first)}\n")
    let key=CacheKey(scene=2,entity=7)
    verify(derive_equal(key,key) && derive_hash(key)==derive_hash(key))
    print("Derive custom demo OK\n")
}
