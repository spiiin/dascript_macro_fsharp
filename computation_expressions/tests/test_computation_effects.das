options gen2
require ../support/game_state_example.das

struct OtherState { number : int }

def test_state() {
    let initial = GameState(health=100, gold=5, turns=0)
    let alive = play_turn(initial, 25, 3)
    assert(alive.value && alive.state.health == 75 && alive.state.gold == 8 && alive.state.turns == 1)
    let dead = play_turn(initial, 200, 3)
    assert(!dead.value && dead.state.health == 0 && dead.state.gold == 5)
    assert(initial.health == 100 && initial.gold == 5 && initial.turns == 0)
    let again = play_turn(initial, 25, 3)
    assert(again.state.health == alive.state.health && again.state.gold == alive.state.gold)
    var builder_count = 0
    var source_count = 0
    let context = computation(counted_builder(initial, builder_count)) {
        let before = state_get() |> bind
        var changed = before
        changed.gold = 9
        counted_put(changed, source_count) |> bind
        let after = state_get() |> bind
        assert(before.gold == 5 && after.gold == 9)
        return after.gold
    }
    assert(context.value == 9 && context.state.gold == 9)
    assert(builder_count == 1 && source_count == 1)

    // An inner workflow has its own context until explicitly bound/imported.
    let nested = computation(StateBuilder(initial)) {
        let inner = play_turn(initial, 10, 2)
        let untouched = state_get() |> bind
        assert(untouched.health == 100)
        let survived = inner |> bind
        let adopted = state_get() |> bind
        assert(survived && adopted.health == 90 && adopted.gold == 7)
        return "adopted"
    }
    assert(nested.value == "adopted" && nested.state.health == 90)
    let forwarded = computation(StateBuilder(initial)) {
        return play_turn(initial, 20, 0) |> return_from
    }
    assert(forwarded.value && forwarded.state.health == 80)
    let empty_state = computation(StateBuilder(initial)) {}
    assert(empty_state.state.health == 100 && empty_state.state.gold == 5)

    // Preparing a put does not execute it; zero-iteration loops preserve state.
    let prepared = computation(StateBuilder(1)) {
        let unused_put = state_put(999)
        let before = state_get() |> bind
        assert(before == 1)
        state_put(2) |> bind
        for (i in range(0)) { state_put(100) |> bind }
        while (false) { state_put(200) |> bind }
        let after = state_get() |> bind
        return after
    }
    assert(prepared.value == 2 && prepared.state == 2)

    // Different state type and 10,000 native-loop iterations.
    let numeric = computation(StateBuilder(0)) {
        for (i in range(10000)) {
            let n = state_get() |> bind
            state_put(n + 1) |> bind
        }
        return "done"
    }
    assert(numeric.value == "done" && numeric.state == 10000)
    let other = computation(StateBuilder(OtherState(number=7))) {
        var s = state_get() |> bind
        s.number++
        state_put(s) |> bind
    }
    assert(other.state.number == 8)
    for (count in range(4)) {
        let loops = computation(StateBuilder(0)) {
            for (i in range(count)) {
                var j = 0
                while (j < 2) {
                    let n = state_get() |> bind
                    state_put(n + 1) |> bind
                    j++
                }
            }
        }
        assert(loops.state == count * 2)
    }
    // A terminal branch/loop must preserve the latest state, including return_from.
    let branch = computation(StateBuilder(0)) {
        if (true) { return state_result(42, 9) |> return_from }
        else { return 0 }
    }
    assert(branch.value == 42 && branch.state == 9)
    let imported_iteration = computation(StateBuilder(0)) {
        for (i in range(3)) {
            return state_result(CeUnit(), i + 1) |> return_from
        }
    }
    assert(imported_iteration.state == 3)
}
def counted_builder(initial : GameState; var calls : int&) {
    calls++
    return StateBuilder(initial)
}
def counted_put(value : GameState; var calls : int&) {
    calls++
    return state_put(value)
}
def recorded(message : string; var calls : int&) {
    calls++
    return writer_value(7, message)
}
def test_writer() {
    var calls = 0
    let result = computation(WriterBuilder()) {
        tell("A") |> bind
        let n = recorded("B", calls) |> bind
        if (n == 7) { tell("C") |> bind }
        else { tell("WRONG") |> bind }
        for (i in range(3)) {
            tell("{i}") |> bind
            var j = 0
            while (j < 2) {
                tell("x") |> bind
                j++
            }
        }
        tell("D") |> bind
        return "value={n}"
    }
    assert(result.value == "value=7" && result.log == "ABC0xx1xx2xxD" && calls == 1)
    let empty_writer = computation(WriterBuilder()) {}
    assert(empty_writer.log == "")
    let no_return = computation(WriterBuilder()) { tell("unit") |> bind }
    assert(no_return.log == "unit")
    let nested = computation(WriterBuilder()) {
        tell("before;") |> bind
        let inner = computation(WriterBuilder()) {
            tell("inner;") |> bind
            return 12
        }
        let n = inner |> bind
        tell("after;") |> bind
        return n
    }
    assert(nested.value == 12 && nested.log == "before;inner;after;")
    let forwarded = computation(WriterBuilder()) {
        tell("a") |> bind
        return writer_value(42, "b") |> return_from
    }
    assert(forwarded.value == 42 && forwarded.log == "ab")
    let branch = computation(WriterBuilder()) {
        tell("a") |> bind
        if (false) { return writer_value(0, "bad") |> return_from }
        else { return writer_value(1, "b") |> return_from }
    }
    assert(branch.value == 1 && branch.log == "ab")
    for (count in range(5)) {
        var expected = ""
        for (i in range(count)) { expected += "{i};" }
        let terminal_for = computation(WriterBuilder()) {
            for (i in range(count)) { tell("{i};") |> bind }
        }
        var index = 0
        let terminal_while = computation(WriterBuilder()) {
            while (index < count) {
                tell("{index};") |> bind
                index++
            }
        }
        assert(terminal_for.log == expected && terminal_while.log == expected)
    }
    let independent = computation(WriterBuilder()) {
        let ignored = tell("not bound")
        return 1
    }
    assert(independent.log == "")
    // Result is merely a payload here: Writer does not gain failure semantics.
    let payload = computation(WriterBuilder()) {
        tell("kept") |> bind
        return result_error("failure as data", type<int>)
    }
    assert(payload.value is err && payload.log == "kept")
}
[export]
def main() {
    test_state()
    test_writer()
    print("state/writer checks OK: snapshots, isolation, composition, loops, exact log order\n")
}

