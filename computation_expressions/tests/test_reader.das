options gen2
require ../lib/computation.das
require ../lib/reader_builder.das

var constructed = 0
var cleaned = 0
struct TestResource {}
def ce_dispose(var resource : TestResource) { cleaned++ }
def counted_reader() {
    constructed++
    return ReaderBuilder(7)
}
[export]
def main() {
    var total = 0
    let value = computation(counted_reader()) {
        let environment = reader_ask() |> bind
        reader_value(123) |> bind
        for (i in range(3)) {
            let n = reader_ask() |> bind
            total += n + i
        }
        var remaining = 2
        while (remaining > 0) { total += environment; remaining-- }
        if (environment == 7) { total++ }
        let resource = TestResource() |> use_resource
        try_finally($ { total++ }, $ { cleaned++ })
        return environment + total
    }
    assert(value.value == 47)
    assert(constructed == 1 && cleaned == 2)
    let recovered = computation(ReaderBuilder("config")) {
        try_with($ { panic("failure"); return "unreachable" }, $(message:string) {
            let environment = reader_ask() |> bind
            return environment
        })
    }
    assert(recovered.value == "config")
    let forwarded = computation(ReaderBuilder(0)) { return reader_value(42) |> return_from }
    assert(forwarded.value == 42)
    let empty = computation(ReaderBuilder(0)) {}
    let unit : CeUnit = empty.value
    print("reader checks OK\n")
}
