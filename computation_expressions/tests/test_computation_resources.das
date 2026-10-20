options gen2
require ../lib/computation.das
require daslib/rtti
require strings
struct TestResource { id : int }
var events = ""
var dispose_failure = 0
var acquire_failure = 0

def acquire(id : int) {
    events += "open{id};"
    if (id == acquire_failure) { panic("acquisition failed") }
    return TestResource(id=id)
}
def ce_dispose(var handle : TestResource) {
    events += "close{handle.id};"
    if (handle.id == dispose_failure) { panic("disposal failed") }
}
def fail_source(builder : ResultBuilder) { return result_error("stop", type<int>) }
def fail_source(builder : OptionBuilder) { return none(type<int>) }
def fail_source(builder : WriterResultBuilder) { return result_error("stop", type<int>) }
def fail_source(builder : tuple<kind : StateResultContext; initial : auto(S); state : S>) {
    return result_error("stop", type<int>)
}
def test_success(builder : auto) {
    events = ""
    let output = computation(builder) {
        try_finally($ {
            let a = acquire(1) |> use_resource
            let b = acquire(2) |> use_resource
            let n = ce_return(builder, 40) |> bind
            return n + a.id + b.id
        }, $ { events += "finally;" })
    }
    assert(ce_unwrap(builder, output) == 43)
    assert(events == "open1;open2;close2;close1;finally;")
    events = ""
    let looped = computation(builder) {
        for (i in range(1, 4)) {
            let resource = acquire(i) |> use_resource
            events += "body{resource.id};"
        }
        return 1
    }
    assert(ce_unwrap(builder, looped) == 1)
    assert(events == "open1;body1;close1;open2;body2;close2;open3;body3;close3;")
    events = ""
    let scoped = computation(builder) {
        if (true) {
            let branch_resource = acquire(1) |> use_resource
        }
        events += "after_branch;"
        var i = 2
        while (i < 4) {
            let loop_resource = acquire(i) |> use_resource
            i++
        }
        return 1
    }
    assert(events == "open1;close1;after_branch;open2;close2;open3;close3;")
    events = ""
    let unit_value = computation(builder) {
        try_finally($ {}, $ { events += "empty;" })
        try_finally($ { let resource = acquire(1) |> use_resource }, $ { events += "last;" })
    }
    assert(events == "empty;open1;close1;last;")
}
def test_failure(builder : auto) {
    events = ""
    let output = computation(builder) {
        try_finally($ {
            let a = acquire(1) |> use_resource
            let b = acquire(2) |> use_resource
            fail_source(builder) |> bind
            let c = acquire(3) |> use_resource
            events += "WRONG;"
            return 42
        }, $ { events += "finally;" })
    }
    assert(events == "open1;open2;close2;close1;finally;")
    events = ""
    let before_acquire = computation(builder) {
        try_finally($ {
            fail_source(builder) |> bind
            let never = acquire(1) |> use_resource
        }, $ { events += "finally;" })
    }
    assert(events == "finally;")
    events = ""
    let nested_loop = computation(builder) {
        let outer = acquire(1) |> use_resource
        for (i in range(2, 5)) {
            try_finally($ {
                let inner = acquire(i) |> use_resource
                if (i == 3) { fail_source(builder) |> bind }
            }, $ { events += "iteration;" })
        }
        events += "WRONG;"
    }
    assert(events == "open1;open2;close2;iteration;open3;close3;iteration;close1;")
}
def test_exceptions() {
    events = ""
    var caught = ""
    try {
        let output = computation(ResultBuilder()) {
            try_finally($ {
                let a = acquire(1) |> use_resource
                let b = acquire(2) |> use_resource
                panic("body sentinel")
                return 42
            }, $ { events += "finally;" })
        }
    } recover { caught = "{this_context().last_exception}" }
    assert(events == "open1;open2;close2;close1;finally;")
    assert(caught |> starts_with("body sentinel"))

    events = ""
    acquire_failure = 2
    try {
        let output = computation(ResultBuilder()) {
            let a = acquire(1) |> use_resource
            let b = acquire(2) |> use_resource
            return 42
        }
    } recover { caught = "{this_context().last_exception}" }
    acquire_failure = 0
    assert(events == "open1;open2;close1;")
    assert(caught |> starts_with("acquisition failed"))

    events = ""
    dispose_failure = 2
    try {
        let output = computation(ResultBuilder()) {
            try_finally($ {
                let a = acquire(1) |> use_resource
                let b = acquire(2) |> use_resource
                return 42
            }, $ { events += "finally;" })
        }
    } recover { caught = "{this_context().last_exception}" }
    dispose_failure = 0
    assert(events == "open1;open2;close2;close1;finally;")
    assert(caught |> starts_with("disposal failed"))

    events = ""
    dispose_failure = 1
    try {
        let output = computation(ResultBuilder()) {
            try_finally($ {
                let a = acquire(1) |> use_resource
                panic("original body failure")
                return 42
            }, $ { events += "finally;" })
        }
    } recover { caught = "{this_context().last_exception}" }
    dispose_failure = 0
    assert(events == "open1;close1;finally;")
    assert(caught |> starts_with("disposal failed"))

    events = ""
    try {
        let output = computation(ResultBuilder()) {
            try_finally($ {
                try_finally($ { return 1 }, $ { events += "cleanup;"; panic("cleanup failed") })
            }, $ { events += "outer;" })
        }
    } recover { caught = "{this_context().last_exception}" }
    assert(events == "cleanup;outer;")
    assert(caught |> starts_with("cleanup failed"))
}
def test_effects() {
    events = ""
    let wr = computation(WriterResultBuilder()) {
        try_finally($ {
            let resource = acquire(1) |> use_resource
            tell("before") |> bind
            return writer_result_error("stop", type<int>, ";failure") |> return_from
        }, $ { events += "finally;" })
    }
    assert(wr.result is err && (wr.result as err) == "stop" && wr.log == "before;failure")
    assert(events == "open1;close1;finally;")
    events = ""
    let sr = computation(StateResultBuilder(10)) {
        try_finally($ {
            let resource = acquire(1) |> use_resource
            state_put(20) |> bind
            return result_error("rollback", type<int>) |> return_from
        }, $ { events += "finally;" })
    }
    assert(sr.result is err && (sr.result as err) == "rollback" && sr.state == 10)
    assert(events == "open1;close1;finally;")
}
[export]
def main() {
    test_success(ResultBuilder())
    test_success(OptionBuilder())
    test_success(WriterBuilder())
    test_success(StateBuilder(10))
    test_success(WriterResultBuilder())
    test_success(StateResultBuilder(10))
    test_failure(ResultBuilder())
    test_failure(OptionBuilder())
    test_failure(WriterResultBuilder())
    test_failure(StateResultBuilder(10))
    test_exceptions()
    test_effects()
    print("resources checks OK: six builders, LIFO, loops, short circuit, panic, acquisition/disposal failures\n")
}

