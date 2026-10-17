options gen2
require ../support/move_collection_support.das
require daslib/rtti
require daslib/strings_boost
var steps=0

def lists() {
    let baseline=heap_bytes_allocated()
    {
        var inscope counts <- computation(ListBuilder()) {
            var value & = loot_list() |> bind
            return length(value.items)
        }
        assert(length(counts)==3 && counts[0]==1)
        var inscope generated <- computation(ListBuilder(type<Loot>)) {
            let n=fixed_array(7,8) |> bind
            return <- loot(n)
        }
        assert(length(generated)==2 && generated[1].items[0]==8)
        var inscope input <- loot_list()
        var inscope output <- computation(ListBuilder(type<Loot>)) {
            var value & = input |> bind
            value.items |> push(99)
            return <- value
        }
        assert(length(input)==0 && length(output)==3 && output[2].items[1]==99)
        var inscope forwarded <- computation(ListBuilder(type<Loot>)) {return loot_list() |> return_from}
        assert(length(forwarded)==3)
        var inscope combined <- computation(ListBuilder(type<Loot>)) {
            for(i in range(3)) {yield <- loot(i)}
            loot_list() |> yield_from
        }
        assert(length(combined)==6)
        var inscope discarded <- computation(ListBuilder(type<Loot>)) {loot_list() |> bind}
        assert(length(discarded)==0)
    }
    var caught=false
    try {
        var inscope bad <- computation(ListBuilder(type<Loot>)) {
            var value & = loot_list() |> bind
            steps++
            if(value.items[0]==20) {panic("list body failed")}
            return <- value
        }
    } recover {caught=true}
    assert(caught && steps==2)
    steps=0
    let current=heap_bytes_allocated();assert(current==baseline)
}
def sequence_completion_and_break() {
    let baseline=heap_bytes_allocated()
    {
        var inscope source <- upgraded_loot()
        var count=0
        for(value in source) {assert(length(value.items)==2);count++}
        assert(count==3 && feeds_opened==feeds_closed)
    }
    {
        var inscope source <- upgraded_loot()
        for(value in source) {assert(value.items[0]==10);break}
        assert(feeds_opened==feeds_closed)
    }
    {
        var inscope unopened <- upgraded_loot()
    }
    assert(feeds_opened==feeds_closed)
    let current=heap_bytes_allocated();assert(current==baseline)
}
def take_ownership() {
    let baseline=heap_bytes_allocated()
    {
        var inscope kept:Loot
        {
            var inscope source <- upgraded_loot()
            for(value in source) {kept <- value;assert(length(value.items)==0);break}
        }
        assert(length(kept.items)==2 && kept.items[0]==10)
    }
    {
        var inscope kept:array<Loot>
        var inscope source <- upgraded_loot()
        sequence_each_move(source) $(var value:Loot) {kept |> emplace(value)}
        assert(length(kept)==3 && kept[2].items[0]==30)
    }
    assert(feeds_opened==feeds_closed)
    let current=heap_bytes_allocated();assert(current==baseline)
}
def sequence_failures() {
    let baseline=heap_bytes_allocated()
    var caught=false
    {
        var inscope source <- upgraded_loot(true)
        try {sequence_each(source) $(value:Loot) {steps++}} recover {
            caught=true
            assert(starts_with(this_context().last_exception,"loot source failed"))
        }
    }
    assert(caught && steps==1);steps=0
    caught=false
    {
        var inscope source <- upgraded_loot()
        try {sequence_each(source) $(value:Loot) {panic("consumer failed")}} recover {caught=true}
    }
    assert(caught)
    assert(feeds_opened==feeds_closed)
    let current=heap_bytes_allocated();assert(current==baseline)
}
def forwarding() {
    let baseline=heap_bytes_allocated()
    {
        var inscope source <- computation(SequenceBuilder(type<Loot>)) {upgraded_loot() |> yield_from}
        for(value in source) {assert(value.items[0]==10);break}
        assert(feeds_opened==feeds_closed)
    }
    {
        var inscope source <- computation(SequenceBuilder(type<Loot>)) {
            try_with($ {loot_sequence(true) |> yield_from}, $(message:string) {yield <- loot(-1)})
        }
        var count=0
        sequence_each(source) $(value:Loot) {count++;assert(value.items[0]==(count==1 ? 10 : -1))}
        assert(count==2)
    }
    assert(feeds_opened==feeds_closed)
    let current=heap_bytes_allocated();assert(current==baseline)
}

def nested_consumer_failure() {
    let baseline=heap_bytes_allocated()
    var caught=false
    {
        var inscope source <- computation(SequenceBuilder(type<Loot>)) {
            var value & = loot_sequence() |> bind
            if(value.items[0]==20) {panic("nested consumer failed")}
            yield <- value
        }
        try {sequence_each(source) $(value:Loot) {steps++}} recover {caught=true}
    }
    assert(caught && steps==1 && feeds_opened==feeds_closed);steps=0
    {
        var inscope source <- loot_list()
        for(value in source) {assert(value.items[0]==10);break}
        assert(feeds_opened==feeds_closed)
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}


def list_cleanup() {
    let baseline=heap_bytes_allocated()
    var closed=0
    {
        var inscope values <- computation(ListBuilder(type<Loot>)) {
            try_finally($ {loot_list() |> yield_from}, $ {closed++})
        }
        assert(length(values)==3 && closed==1)
    }
    var caught=false
    try {
        var inscope values <- computation(ListBuilder(type<Loot>)) {
            try_finally($ {loot_list() |> yield_from}, $ {closed++;panic("list cleanup")})
        }
    } recover {caught=true}
    assert(caught && closed==2)
    let current=heap_bytes_allocated();assert(current==baseline)
}


def nested_arrays() {
    let baseline=heap_bytes_allocated()
    {
        var inscope values <- computation(ListBuilder(type<array<int>>)) {yield <- [1,2];yield <- [3,4]}
        assert(length(values)==2 && values[1][1]==4)
        var inscope source <- computation(SequenceBuilder(type<array<int>>)) {yield <- [5,6];yield <- [7,8]}
        for(value in source) {assert(value[0]==5);break}
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}

[export]
def main() {
    for(round in range(5)) {lists();sequence_completion_and_break();take_ownership();sequence_failures();forwarding();nested_consumer_failure();list_cleanup();nested_arrays()}
    print("move-only collection checks OK\n")
}
