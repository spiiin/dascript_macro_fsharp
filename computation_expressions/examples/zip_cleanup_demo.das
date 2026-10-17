options gen2
require ../lib/computation.das
var closed=0
struct Feed {}
def ce_dispose(var feed:Feed) {closed++}
def damage_feed() {
    return <- computation(SequenceBuilder()) {
        let feed=Feed() |> use_resource
        yield 10
        yield 20
        panic("damage feed disconnected")
    }
}
[export]
def main() {
    var inscope health <- [100,200,300]
    let result=computation(ResultBuilder()) {
        try_with($ {
            for (hp,damage in health,damage_feed()) {hp-=damage}
            return 0
        }, $(message:string) {
            assert(closed==1)
            print("Recovered after closing feed: {message}\n")
            return -1
        })
    }
    assert(result as ok==-1 && health[0]==90 && health[1]==180 && health[2]==300)
    // The failed traversal also released the array lock.
    health |> push(400)
    print("zip cleanup demo OK\n")
}
