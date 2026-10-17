options gen2
require ../lib/computation.das
require daslib/rtti
require strings
struct Counters { builder : int; source : int; next_source : int; finish : int }
struct Item { id : int }
struct Handle { id : int }
var events = ""
def acquire(id : int) { events += "open{id};"; return Handle(id=id) }
def ce_dispose(var h : Handle) { events += "close{h.id};" }
def builder(var counts : Counters) { counts.builder++; return ListBuilder() }
def first(var counts : Counters) { counts.source++; return [1, 2] }
def second(var counts : Counters; x : int) { counts.next_source++; return [x * 10, x * 20] }
def dynamic_values() { return <- to_array([4, 5]) }
def test_bind() {
    var counts : Counters
    var inscope values <- computation(builder(counts)) {
        let x = first(counts) |> bind
        let y = second(counts, x) |> bind
        counts.finish++
        return x + y
    }
    assert(length(values) == 4 && values[0] == 11 && values[1] == 21 && values[2] == 22 && values[3] == 42)
    assert(counts.builder == 1 && counts.source == 1 && counts.next_source == 2 && counts.finish == 4)
    var inscope temporary_source <- computation(ListBuilder()) {
        let x = dynamic_values() |> bind
        return x * 2
    }
    assert(length(temporary_source) == 2 && temporary_source[0] == 8 && temporary_source[1] == 10)
    var inscope empty_source : array<int>
    var inscope empty_result <- computation(ListBuilder()) {
        empty_source |> bind
        counts.finish++
        return 123
    }
    assert(empty(empty_result) && counts.finish == 4)
    var inscope dynamic_source <- to_array([3, 3, 1])
    var inscope dynamic_result <- computation(ListBuilder(type<string>)) {
        let n : int = dynamic_source |> bind
        return "n={n}"
    }
    assert(length(dynamic_result) == 3 && dynamic_result[0] == "n=3" && dynamic_result[1] == "n=3" && dynamic_result[2] == "n=1")
    assert(length(dynamic_source) == 3 && dynamic_source[0] == 3)
    var inscope forwarded <- computation(ListBuilder()) { return dynamic_source |> return_from }
    forwarded[0] = 99
    assert(dynamic_source[0] == 3)
    var inscope fixed_forwarded <- computation(ListBuilder()) { return [7, 8] |> return_from }
    assert(length(fixed_forwarded) == 2 && fixed_forwarded[1] == 8)
    var inscope copied_values <- computation(ListBuilder()) {
        var x = [1, 2] |> bind
        x += 5
        return x
    }
    assert(copied_values[0] == 6 && copied_values[1] == 7)
    var inscope items <- computation(ListBuilder(type<Item>)) {
        let x = [1, 2] |> bind
        return Item(id=x)
    }
    assert(length(items) == 2 && items[1].id == 2)
}
def test_control() {
    var inscope zero <- computation(ListBuilder(type<string>)) {}
    assert(empty(zero))
    var inscope filtered <- computation(ListBuilder()) {
        let x = [1, 2, 3, 4] |> bind
        if (x % 2 == 0) { return x }
    }
    assert(length(filtered) == 2 && filtered[0] == 2 && filtered[1] == 4)
    var inscope combined <- computation(ListBuilder()) {
        if (true) { return 1 }
        if (false) { return 99 }
        return [2, 3] |> return_from
    }
    assert(length(combined) == 3 && combined[0] == 1 && combined[1] == 2 && combined[2] == 3)
    var inscope loops <- computation(ListBuilder()) {
        for (i in range(3)) {
            let j = [10, 20] |> bind
            return i + j
        }
        var n = 0
        while (n < 2) {
            n++
            return n * 100
        }
    }
    assert(length(loops) == 8 && loops[0] == 10 && loops[5] == 22 && loops[6] == 100 && loops[7] == 200)
    var visits = 0
    var inscope side_effects <- computation(ListBuilder()) {
        [1, 2, 3] |> bind
        visits++
    }
    assert(empty(side_effects) && visits == 3)
    var inscope nested <- computation(ListBuilder()) {
        let n = [1, 2] |> bind
        var inscope inner <- computation(ListBuilder()) {
            let x = [10, 20] |> bind
            return n + x
        }
        let x = inner |> bind
        let optional = computation(OptionBuilder()) { return x * 2 }
        return optional as some
    }
    assert(length(nested) == 4 && nested[0] == 22 && nested[3] == 44)
    var inscope long_loop <- computation(ListBuilder()) {
        for (i in range(10000)) { return i }
    }
    assert(length(long_loop) == 10000 && long_loop[9999] == 9999)
}
def test_resources() {
    events = ""
    var inscope result <- computation(ListBuilder()) {
        try_finally($ {
            let outer = acquire(9) |> use_resource
            let n = [1, 2] |> bind
            let inner = acquire(n) |> use_resource
            return n
        }, $ { events += "finally;" })
    }
    assert(length(result) == 2 && result[0] == 1 && result[1] == 2)
    assert(events == "open9;open1;close1;open2;close2;close9;finally;")
    events = ""
    var inscope no_values : array<int>
    var inscope discarded <- computation(ListBuilder()) {
        let outer = acquire(9) |> use_resource
        no_values |> bind
        let inner = acquire(1) |> use_resource
        return 1
    }
    assert(empty(discarded) && events == "open9;close9;")
    events = ""
    var caught = false
    try {
        var inscope panic_result <- computation(ListBuilder()) {
            try_finally($ {
                let n = [1, 2, 3] |> bind
                let h = acquire(n) |> use_resource
                if (n == 2) { panic("list sentinel") }
                return n
            }, $ { events += "finally;" })
        }
    } recover { caught = this_context().last_exception |> starts_with("list sentinel") }
    assert(caught && events == "open1;close1;open2;close2;finally;")
}
[export]
def main() {
    test_bind()
    test_control()
    test_resources()
    print("list checks OK: products, order, empty sources, effects, typed results, loops, resources\n")
}

