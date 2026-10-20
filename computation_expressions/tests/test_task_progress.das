options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require ../lib/task_progress.das
require daslib/rtti

struct LoadProgress {done:int;total:int}

var shown:array<int>
// Application-level service, as in the channel examples.
var load_progress:typedecl(task_progress(type<LoadProgress>))

def loader() {
    return <- computation(TaskBuilder(type<int>)) {
        for(i in range(4)) {
            task_after_polls(1,0) |> bind
            task_progress_report(load_progress,LoadProgress(done=i+1,total=4))
        }
        task_progress_close(load_progress)
        return 4
    }
}
def observer() {
    return <- computation(TaskResultBuilder(type<int>)) {
        var updates=0
        while(true) {
            let next=task_progress_wait(load_progress) |> bind
            if(next is none) {break}
            shown |> push((next as some).done)
            updates++
        }
        return updates
    }
}

def checks() {
    {
        var inscope progress <- task_progress(type<int>)
        verify(task_progress_value(progress) is none && task_progress_version(progress)==uint64(0))
        verify(task_progress_report(progress,10) && task_progress_version(progress)==uint64(1))
        verify(task_progress_value(progress) as some==10)
        // A wait observes the version at its first poll, not at construction.
        var inscope wait <- task_progress_wait(progress)
        verify(task_progress_report(progress,20))
        verify(task_poll(wait)==TaskStatus.Waiting)
        task_progress_report(progress,30)
        task_progress_report(progress,40) // coalesced: the wait sees only the latest
        verify(task_poll(wait)==TaskStatus.Succeeded && (wait.value as ok) as some==40)
        // wait_after does not lose an update made before its first poll.
        let seen=task_progress_version(progress)
        task_progress_report(progress,50)
        var inscope after <- task_progress_wait_after(progress,seen)
        verify(task_poll(after)==TaskStatus.Succeeded && (after.value as ok) as some==50)
        var inscope ending <- task_progress_wait(progress)
        verify(task_poll(ending)==TaskStatus.Waiting)
        task_progress_close(progress)
        verify(!task_progress_report(progress,60) && task_progress_closed(progress))
        verify(task_poll(ending)==TaskStatus.Succeeded && (ending.value as ok) is none)
        verify(task_progress_value(progress) as some==50)
    }
    {
        // Producer task and a UI observer task in one runtime.
        delete shown
        load_progress <- task_progress(type<LoadProgress>)
        var inscope runtime <- task_runtime()
        var inscope job <- task_spawn(runtime,loader())
        var inscope ui <- task_spawn(runtime,observer())
        for(t in range(20)) {task_tick(runtime,t)}
        verify(task_value(job)==4 && task_status(ui)==TaskStatus.Succeeded)
        verify(task_value(ui) is ok && length(shown)>=1 && shown[length(shown)-1]==4)
        delete runtime
        delete load_progress
    }
    {
        // Owner destruction closes; pending waits hold the state until finished.
        var inscope wait:typedecl(task_progress_wait(task_progress(type<int>)))
        {
            var inscope progress <- task_progress(type<int>)
            wait <- task_progress_wait(progress)
            task_poll(wait)
        }
        verify(task_poll(wait)==TaskStatus.Succeeded && (wait.value as ok) is none)
        var inscope progress <- task_progress(type<int>)
        var inscope cancelled <- task_progress_wait(progress)
        task_poll(cancelled);verify(task_cancel(cancelled))
    }
    delete shown
}

[export]
def main() {
    checks();let baseline=heap_bytes_allocated()
    for(i in range(5)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task progress checks OK\n")
}
