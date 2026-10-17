options gen2
require ../lib/computation_macro.das
require ../support/protocol_test_builders.das
require ../support/protocol_collect_fixture.das

var closes = 0
var steps = 0
struct Resource {}
def ce_dispose(var resource : Resource) { closes++ }
[export]
def main() {
    var inscope totals <- computation(ExternalCollectionBuilder()) {
        yield 1
        for (i in range(4)) { yield i }
        if (true) { yield 10 }
        [20] |> yield_from
    }
    var total = 0
    for (value in totals) { total += value }
    assert(total == 37)
    var inscope recovered <- computation(ExternalCollectionBuilder()) {
        try_with($ { for (i in range(3)) { yield i; panic("failure") } }, $(message:string) { yield 99 })
    }
    assert(length(recovered) == 1 && recovered[0] == 99)
    {
        var inscope values <- computation(custom_sequence()) {
            let resource = Resource() |> use_resource
            steps++
            yield "one"
            steps++
            yield "two"
        }
        assert(sequenceConstructors == 1 && sequenceRuns == 1 && steps == 0)
        for (value in values) { assert(value == "one"); break }
        assert(closes == 1 && steps == 1)
    }
    {
        var inscope values <- computation(custom_sequence()) { yield "complete" }
        for (value in values) { assert(value == "complete") }
    }
    var caught = false
    try {
        var inscope values <- computation(custom_sequence()) {
            let resource = Resource() |> use_resource
            panic("failure")
            yield "unreachable"
        }
        for (value in values) { assert(false) }
    } recover { caught = true }
    assert(caught && closes == 2)
    assert(sequenceConstructors == 3 && sequenceRuns == 3)
    assert(protocolCalls == 0)
    print("builder protocol checks OK\n")
}

