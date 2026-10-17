options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
require daslib/rtti
require daslib/strings_boost
def inventory() {
    var inscope items <- [1,2,3]
    return <- move_ok(items)
}
def optional_inventory() {
    var inscope items <- [4,5]
    return <- move_some(items)
}
def upgrade() {
    return <- computation(MoveResultBuilder()) {
        var items & = inventory() |> bind
        items |> push(4)
        return <- items
    }
}
var after=0
var disposed=0
struct Handle {}
def ce_dispose(var h:Handle) {disposed++}
def success() {
    let baseline=heap_bytes_allocated()
    {
        var inscope initial <- inventory()
        var inscope result <- computation(MoveResultBuilder()) {
            var items & = initial |> bind
            items |> push(9)
            return <- items
        }
        assert(length(initial as ok)==0)
        assert(length(result as ok)==4 && (result as ok)[3]==9)
        var inscope from_function <- upgrade()
        assert(length(from_function as ok)==4)
        var inscope option <- computation(MoveOptionBuilder()) {
            var items & = optional_inventory() |> bind
            items |> push(6)
            return <- items
        }
        assert(length(option as some)==3)
    }
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
def failures() {
    let baseline=heap_bytes_allocated()
    {
        var inscope result <- computation(MoveResultBuilder()) {
            var items & = inventory() |> bind
            move_error("stop",type<CeUnit>) |> bind
            after++
            return <- items
        }
        assert(result is error && result as error=="stop" && after==0)
        var inscope option <- computation(MoveOptionBuilder()) {
            var items & = optional_inventory() |> bind
            move_none(type<CeUnit>) |> bind
            after++
            return <- items
        }
        assert(option is none && after==0)
    }
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
def panic_cleanup() {
    let baseline=heap_bytes_allocated()
    var caught=false
    try {
        var inscope result <- computation(MoveResultBuilder()) {
            var items & = inventory() |> bind
            panic("payload panic")
            return <- items
        }
    } recover {caught=true;assert(starts_with(this_context().last_exception,"payload panic"))}
    assert(caught)
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
def groups() {
    let baseline=heap_bytes_allocated()
    {
        var inscope result <- computation(MoveResultBuilder()) {
            var pair & = inventory() |> and_bind(inventory()) |> bind
            pair.first |> push(7)
            return <- pair
        }
        assert(length((result as ok).first)==4 && length((result as ok).second)==3)
        var inscope failed <- computation(MoveResultBuilder()) {
            var pair & = move_error("left",type<array<int>>) |> and_bind(inventory()) |> bind
            after++
            return <- pair
        }
        assert(failed is error && after==0)
    }
    let current=heap_bytes_allocated()
    assert(baseline==current)
}
def control() {
    let baseline=heap_bytes_allocated()
    {
        var attempted=0
        var inscope result <- computation(MoveResultBuilder()) {
            var items & = inventory() |> bind
            for(i in range(5)) {
                attempted++
                if(i==2) {move_error("loop",type<CeUnit>) |> bind}
            }
            after++
            return <- items
        }
        assert(result is error && attempted==3 && after==0)
        var inscope forwarded <- computation(MoveResultBuilder()) {return inventory() |> return_from}
        assert(length(forwarded as ok)==3)
        var inscope recovered <- computation(MoveResultBuilder()) {
            try_with($ {
                var items & = inventory() |> bind
                panic("recover")
                return <- items
            }, $(message:string) {return inventory() |> return_from})
        }
        assert(length(recovered as ok)==3)
        var inscope scoped <- computation(MoveResultBuilder()) {
            let handle=Handle() |> use_resource
            var items & = inventory() |> bind
            return <- items
        }
        assert(length(scoped as ok)==3)
    }
    let current=heap_bytes_allocated()
    assert(baseline==current)
}

struct Backpack {
    items:array<int>
}
def pack() {
    var inscope p:Backpack
    p.items |> push(42)
    return <- move_ok(p)
}
def explode() : variant<ok:array<int>;error:string> {panic("source panic");return <- move_error("unreachable",type<array<int>>)}
def more_ownership() {
    let baseline=heap_bytes_allocated()
    {
        var inscope p <- computation(MoveResultBuilder()) {
            var bag & = pack() |> bind
            bag.items |> push(8)
            return <- bag
        }
        assert(length((p as ok).items)==2)
        var inscope scalar <- computation(MoveResultBuilder()) {
            let x=move_ok(12) |> bind
            return x+1
        }
        assert(scalar as ok==13)
        var inscope discarded <- computation(MoveResultBuilder()) {inventory() |> bind;return 5}
        assert(discarded as ok==5)
        var inscope right_error <- computation(MoveResultBuilder()) {
            var pair & = inventory() |> and_bind(move_error("right",type<array<int>>)) |> bind
            after++
            return <- pair
        }
        assert(right_error is error && after==0)
        var inscope opt <- computation(MoveOptionBuilder()) {
            var pair & = optional_inventory() |> and_bind(optional_inventory()) |> bind
            return <- pair
        }
        assert(length((opt as some).first)==2 && length((opt as some).second)==2)
        var inscope missing <- computation(MoveOptionBuilder()) {
            var pair & = optional_inventory() |> and_bind(move_none(type<array<int>>)) |> bind
            after++
            return <- pair
        }
        assert(missing is none && after==0)
        var inscope task <- deferred(MoveResultBuilder(),7) $(snapshot) {
            var bag & = pack() |> bind
            bag.items |> push(snapshot)
            return <- bag
        }
        var inscope a <- run_deferred(task)
        var inscope b <- run_deferred(task)
        (a as ok).items[0]=99
        assert((b as ok).items[0]==42 && (b as ok).items[1]==7)
    }
    var caught=false
    try {
        var inscope bad <- computation(MoveResultBuilder()) {
            var pair & = inventory() |> and_bind(explode()) |> bind
            return <- pair
        }
    } recover {caught=true}
    assert(caught)
    let current=heap_bytes_allocated()
    assert(current==baseline)
}
def finally_ownership() {
    let baseline=heap_bytes_allocated()
    var closed=0
    {
        var inscope r <- computation(MoveResultBuilder()) {
            try_finally($ {var items & = inventory() |> bind;return <- items}, $ {closed++})
        }
        assert(length(r as ok)==3 && closed==1)
    }
    var caught=false
    try {
        var inscope r <- computation(MoveResultBuilder()) {
            try_finally($ {var items & = inventory() |> bind;return <- items}, $ {closed++;panic("cleanup")})
        }
    } recover {caught=true}
    assert(caught && closed==2)
    let current=heap_bytes_allocated()
    assert(current==baseline)
}


struct InventoryRequest {}
def ce_source(builder:MoveResultBuilder; request:InventoryRequest) {return <- inventory()}
def owned_loops() {
    let baseline=heap_bytes_allocated()
    {
        var attempts=0
        var inscope stopped <- computation(MoveOptionBuilder()) {
            var items & = optional_inventory() |> bind
            while(attempts<5) {
                attempts++
                if(attempts==2) {move_none(type<CeUnit>) |> bind}
            }
            after++
            return <- items
        }
        assert(stopped is none && attempts==2 && after==0)
        var inscope adapted <- computation(MoveResultBuilder()) {
            var items & = InventoryRequest() |> bind
            return <- items
        }
        assert(length(adapted as ok)==3)
        var closed=0
        var inscope failed <- computation(MoveResultBuilder()) {
            try_finally($ {
                var items & = inventory() |> bind
                move_error("protected",type<CeUnit>) |> bind
                return <- items
            }, $ {closed++})
        }
        assert(failed is error && closed==1)
        var caught=false
        try {
            var inscope r <- computation(MoveOptionBuilder()) {
                try_finally($ {
                    var items & = optional_inventory() |> bind
                    panic("option body")
                    return <- items
                }, $ {closed++})
            }
        } recover {caught=true}
        assert(caught && closed==2)
    }
    let current=heap_bytes_allocated()
    assert(current==baseline)
}

[export]
def main() {
    for(round in range(5)) {success();failures();panic_cleanup();groups();control();more_ownership();finally_ownership();owned_loops()}
    assert(disposed==5)
    print("move-only CE checks OK\n")
}
