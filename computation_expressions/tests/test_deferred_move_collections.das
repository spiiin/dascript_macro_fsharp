options gen2
require ../support/deferred_move_support.das
require daslib/rtti
require daslib/strings_boost

def list_replays() {
    let baseline=heap_bytes_allocated()
    {
        var inscope task <- deferred_loot_list()
        var inscope a <- run_deferred(task)
        var inscope b <- task |> run_deferred
        assert(length(a)==3 && length(b)==3)
        a[0].items[0]=999
        assert(b[0].items[0]==10 && length(b[0].items)==2)
        delete task
        assert(a[2].items[1]==100 && b[2].items[1]==100)
        for(value in a) {break}
    }
    {
        var inscope task <- deferred_loot_list(true)
        let taskHeap=heap_bytes_allocated()
        for(round in range(3)) {
            var caught=false
            try {var inscope bad <- run_deferred(task)} recover {caught=true}
            assert(caught)
            let current=heap_bytes_allocated();assert(current==taskHeap)
        }
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}
def sequence_replays() {
    let baseline=heap_bytes_allocated()
    let freed=snapshot_freed
    let steps=lazy_steps
    {
        var inscope task <- deferred_loot_sequence()
        assert(snapshot_freed==freed+1)
        var inscope a <- run_deferred(task)
        var inscope b <- run_deferred(task)
        assert(lazy_steps==steps && snapshot_freed==freed+1)
        delete task
        assert(snapshot_freed==freed+2)
        var inscope kept:Loot
        for(value in a) {kept <- value;break}
        assert(kept.items[0]==10 && kept.items[1]==200 && snapshot_freed==freed+3)
        kept.items[0]=999
        var count=0
        sequence_each(b) $(value:Loot) {
            assert(value.items[0]==(count+1)*10 && length(value.items)==2)
            count++
        }
        assert(count==3 && snapshot_freed==freed+4)
        assert(kept.items[0]==999)
    }
    assert(feeds_opened==feeds_closed)
    let current=heap_bytes_allocated();assert(current==baseline)
}
def unopened_and_repeated_close() {
    let baseline=heap_bytes_allocated()
    let opened=feeds_opened
    let freed=snapshot_freed
    {
        var inscope task <- deferred_loot_sequence()
        {
            var inscope source <- run_deferred(task)
            sequence_close(source)
            sequence_close(source)
        }
        assert(snapshot_freed==freed+2 && feeds_opened==opened)
    }
    assert(snapshot_freed==freed+3)
    let current=heap_bytes_allocated();assert(current==baseline)
}
def sequence_errors(producer:bool) {
    let baseline=heap_bytes_allocated()
    {
        var inscope task <- deferred_loot_sequence(producer)
        let taskHeap=heap_bytes_allocated()
        for(round in range(3)) {
            let freed=snapshot_freed
            let cleanups=cleanup_count
            var caught=false
            {
                var inscope source <- run_deferred(task)
                try {
                    sequence_each(source) $(value:Loot) {
                        if(!producer) {panic("deferred loot consumer failed")}
                    }
                } recover {
                    caught=true
                    assert(starts_with(this_context().last_exception,producer ? "deferred loot producer failed" : "deferred loot consumer failed"))
                }
                assert(snapshot_freed==freed+1 && cleanup_count==cleanups+1)
                sequence_close(source)
            }
            assert(caught && feeds_opened==feeds_closed)
            let current=heap_bytes_allocated();assert(current==taskHeap)
        }
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}
def transferred_items() {
    let baseline=heap_bytes_allocated()
    {
        var inscope saved:array<Loot>
        var inscope task <- deferred_loot_sequence()
        var inscope source <- run_deferred(task)
        delete task
        sequence_each_move(source) $(var value:Loot) {saved |> emplace(value)}
        assert(length(saved)==3 && saved[2].items[1]==200)
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}

def null_marker_check() {
    let baseline=heap_bytes_allocated()
    {
        var inscope value <- loot(5)
        var builder=ListBuilder(type<Loot>)
        unsafe {builder.element=addr(value)}
        var caught=false
        try {var inscope task <- deferred(builder) {yield <- loot(1)}} recover {
            caught=true
            assert(starts_with(this_context().last_exception,"deferred: move-only builder type marker must be null"))
        }
        assert(caught && value.items[0]==5)
        builder.element=null
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}
def overlapping_runs() {
    let baseline=heap_bytes_allocated()
    {
        var inscope task <- deferred_loot_sequence()
        var inscope a <- run_deferred(task)
        var inscope b <- run_deferred(task)
        delete task
        var outer=0
        var inner=0
        for(first in a) {
            outer++
            if(outer==1) {
                for(second in b) {inner++;assert(second.items[0]==inner*10)}
                // Closing b must not invalidate a's current borrowed element.
                assert(first.items[0]==10 && first.items[1]==200)
            }
        }
        assert(outer==3 && inner==3)
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}


def no_snapshot_and_early_error() {
    let baseline=heap_bytes_allocated()
    {
        var inscope listTask <- deferred(ListBuilder(type<Loot>)) {yield <- loot(7)}
        var inscope a <- run_deferred(listTask)
        var inscope b <- run_deferred(listTask)
        assert(a[0].items[0]==7 && b[0].items[0]==7)
        var inscope task <- deferred(SequenceBuilder(type<Loot>)) {panic("early deferred failure");yield <- loot(9)}
        for(round in range(2)) {
            var inscope source <- run_deferred(task)
            var caught=false
            try {sequence_each(source) $(value:Loot) {assert(false)}} recover {caught=true}
            assert(caught)
        }
        var inscope emptyTask <- deferred(SequenceBuilder(type<Loot>)) {}
        var inscope emptySource <- run_deferred(emptyTask)
        sequence_each(emptySource) $(value:Loot) {assert(false)}
    }
    let current=heap_bytes_allocated();assert(current==baseline)
}

[export]
def main() {
    for(round in range(5)) {
        list_replays();sequence_replays();unopened_and_repeated_close()
        sequence_errors(true);sequence_errors(false);transferred_items();null_marker_check();overlapping_runs();no_snapshot_and_early_error()
    }
    print("deferred move-only collection checks OK\n")
}
