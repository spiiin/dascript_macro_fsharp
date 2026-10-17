options gen2
require ../support/deferred_move_support.das
require daslib/rtti
require daslib/strings_boost

def interleaved() {
    let baseline=heap_bytes_allocated()
    {
        var inscope task <- deferred_loot_sequence()
        var inscope a <- run_deferred(task)
        var inscope b <- run_deferred(task)
        delete task
        let snapshots=snapshot_freed
        var inscope first:Loot
        var inscope second:Loot
        for(i in range(3)) {
            let gotA=sequence_next_move(a,first)
            let gotB=sequence_next_move(b,second)
            assert(gotA && gotB && first.items[0]==10*(i+1) && second.items[0]==10*(i+1))
            first.items[0]=999
            assert(second.items[0]!=999)
        }
        let doneA=sequence_next_move(a,first)
        let doneB=sequence_next_move(b,second)
        assert(!doneA && !doneB && first.items[0]==999 && second.items[0]==30 && snapshot_freed==snapshots+2)
        assert(feeds_opened==feeds_closed)
        let again=sequence_next_move(a,first)
        assert(!again && first.items[0]==999)
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}
def failure() {
    let baseline=heap_bytes_allocated()
    {
        var inscope task <- deferred_loot_sequence(true)
        var inscope stream <- run_deferred(task)
        delete task
        let snapshots=snapshot_freed
        var inscope value:Loot
        let first=sequence_next_move(stream,value)
        assert(first && value.items[0]==10)
        var caught=false
        try {let nextValue=sequence_next_move(stream,value)} recover {
            caught=true
            assert(starts_with(this_context().last_exception,"deferred loot producer failed"))
        }
        assert(caught && value.items[0]==10 && feeds_opened==feeds_closed && snapshot_freed==snapshots+1)
        sequence_close(stream)
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}
def raw_values() {
    let baseline=heap_bytes_allocated()
    {
        var inscope stream <- generator<Loot> {yield <- loot(1);yield <- loot(2);return false}
        var inscope value <- loot(99)
        var count=0
        while(sequence_next_move(stream,value)) {count++}
        assert(count==2 && value.items[0]==2)
    }
    {
        var inscope stream <- loot_sequence()
        var inscope value:Loot
        while(sequence_next_move(stream,value)) {break}
        sequence_close(stream)
        assert(value.items[0]==10 && feeds_opened==feeds_closed)
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}

def raw_failure_and_arrays() {
    let baseline=heap_bytes_allocated()
    {
        var inscope stream <- generator<Loot> {panic("raw producer failed");yield <- loot(2);return false}
        var inscope value <- loot(77)
        var caught=false
        try {let more=sequence_next_move(stream,value)} recover {caught=true}
        assert(caught && value.items[0]==77)
    }
    {
        var inscope stream <- computation(SequenceBuilder(type<array<int>>)) {yield <- [1,2];yield <- [3,4]}
        var inscope value <- [99]
        var count=0
        while(sequence_next_move(stream,value)) {count++}
        assert(count==2 && length(value)==2 && value[0]==3)
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}

[export]
def main() {
    for(round in range(10)) {interleaved();failure();raw_values();raw_failure_and_arrays()}
    print("sequence_next_move ownership checks OK\n")
}
