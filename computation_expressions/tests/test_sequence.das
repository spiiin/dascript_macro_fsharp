options gen2
require ../lib/computation.das
var steps = 0
var sources = 0
var builders = 0
def configured() { builders++; return SequenceBuilder() }
def choices() { sources++; return [10,20] }

def numbers(start : int) {
    return <- computation(SequenceBuilder()) {
        var n = start
        while (true) {
            steps++
            yield n
            n++
        }
    }
}
[export]
def main() {
    var inscope seq <- numbers(10)
    assert(steps == 0)
    var count = 0
    for (value in seq) {
        assert(value == 10+count)
        count++
        if (count == 3) { break }
    }
    assert(count == 3 && steps == 3)
    var inscope product <- computation(SequenceBuilder()) {
        let x = [1,2] |> bind
        let y = [10,20] |> bind
        yield x+y
    }
    var inscope actual : array<int>
    for (value in product) { actual |> push(value) }
    assert(length(actual)==4)
    assert(actual[0]==11 && actual[1]==21 && actual[2]==12 && actual[3]==22)
    var inscope control <- computation(SequenceBuilder()) {
        for (x in range(5)) {
            if (x%2==0) { yield x*x }
        }
        [30,40] |> yield_from
        var i = 0
        while (i<2) { yield i+50; i++ }
    }
    var expected = [0,4,16,30,40,50,51]
    var index = 0
    for (value in control) { assert(value==expected[index]); index++ }
    assert(index==7)
    var inscope empty_seq <- computation(SequenceBuilder()) {}
    for (value in empty_seq) { assert(false) }
    var inscope strings <- computation(SequenceBuilder(type<string>)) {
        yield "a"
        yield "b"
    }
    var text = ""
    for (value in strings) { text += value }
    assert(text=="ab")
    var inscope deferred <- computation(configured()) {
        let x = [1,2] |> bind
        let y = choices() |> bind
        yield x+y
    }
    assert(builders==1 && sources==0)
    for (value in deferred) { assert(value==11); break }
    assert(sources==1)
    var inscope discard <- computation(SequenceBuilder()) {
        [1,2] |> bind
        yield 7
    }
    var hits = 0
    for (value in discard) { assert(value==7); hits++ }
    assert(hits==2)
    var inscope skipped <- computation(SequenceBuilder()) {
        range(0) |> bind
        steps++
        yield 999
    }
    for (value in skipped) { assert(false) }
    assert(steps==3)
    var inscope flattened <- computation(SequenceBuilder()) {
        [1,2] |> yield_from
        [3,4] |> yield_from
    }
    index = 0
    for (value in flattened) { index++; assert(value==index) }
    assert(index==4)
    var inscope nested <- computation(SequenceBuilder()) {
        let value = computation(SequenceBuilder()) { yield 5; yield 6 } |> bind
        yield value*2
    }
    index = 0
    for (value in nested) { assert(value==10+index*2); index++ }
    assert(index==2)
    print("sequence checks OK\n")
}


