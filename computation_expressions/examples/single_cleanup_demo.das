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
    var health=100
    let result=computation(ResultBuilder()) {
        try_with($ {
            for (damage in damage_feed()) {
                let amount=result_ok(damage) |> bind
                health-=amount
            }
            return 0
        }, $(message:string) {
            assert(closed==1)
            print("Recovered after closing feed: {message}\n")
            return -1
        })
    }
    assert(result as ok==-1 && health==70)
    print("single For cleanup demo OK\n")
}
