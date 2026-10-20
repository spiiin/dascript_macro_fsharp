options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require daslib/rtti

var closed=0

def waiting_job() {
    return <- task_from_poll(@(){return task_pending(type<int>)},@(){closed++})
}

def checks() {
    {
        // Child sees the parent request; the parent never sees a child request.
        var inscope level <- cancellation_token()
        var inscope room <- cancellation_child(level)
        var inscope dialog <- cancellation_child(room)
        verify(!cancellation_requested(dialog))
        verify(cancellation_cancel(dialog,"closed by player"))
        verify(cancellation_requested(dialog) && !cancellation_requested(room) && !cancellation_requested(level))
        verify(cancellation_reason(dialog)=="closed by player" && cancellation_reason(room)=="")
        verify(!cancellation_cancel(dialog,"again") && cancellation_reason(dialog)=="closed by player")
        verify(cancellation_cancel(level,"level exit"))
        verify(cancellation_requested(room) && cancellation_reason(room)=="level exit")
        // The nearest requested state wins: the dialog keeps its own reason.
        verify(cancellation_reason(dialog)=="closed by player")
        // An ancestor request does not block recording the child's own request.
        verify(cancellation_cancel(room,"room reset") && cancellation_reason(room)=="room reset")
    }
    {
        // Default reason and clone/view share one state.
        var inscope token <- cancellation_token()
        var inscope view <- cancellation_view(token)
        var inscope copy <- cancellation_clone(view)
        verify(cancellation_is_read_only(view) && cancellation_is_read_only(copy) && !cancellation_is_read_only(token))
        verify(cancellation_cancel(token) && cancellation_requested(view) && cancellation_reason(copy)=="cancelled")
        var failed=false
        try {cancellation_cancel(view)} recover {failed=true}
        verify(failed)
    }
    {
        // A child keeps its ancestors alive after their owners are deleted.
        var inscope child:CancellationToken
        {
            var inscope root <- cancellation_token()
            var inscope middle <- cancellation_child(root)
            child <- cancellation_child(middle)
            verify(cancellation_cancel(root,"shutdown"))
        }
        verify(cancellation_requested(child) && cancellation_reason(child)=="shutdown")
    }
    {
        // Tasks bound to child tokens are cancelled by the parent request.
        let before=closed
        var inscope level <- cancellation_token()
        var inscope roomA <- cancellation_child(level)
        var inscope roomB <- cancellation_child(level)
        var inscope runtime <- task_runtime()
        var inscope a <- task_spawn(runtime,task_with_cancellation(waiting_job(),roomA))
        var inscope b <- task_spawn(runtime,task_with_cancellation(waiting_job(),roomB))
        var inscope other <- task_spawn(runtime,task_after_polls(2,5))
        task_tick(runtime,0)
        verify(cancellation_cancel(roomA,"room A closed"))
        task_tick(runtime,1)
        verify(task_status(a)==TaskStatus.Cancelled && task_status(b)==TaskStatus.Waiting)
        verify(cancellation_cancel(level,"level exit"))
        task_tick(runtime,2)
        verify(task_status(b)==TaskStatus.Cancelled && task_status(other)==TaskStatus.Succeeded)
        verify(closed==before+2 && cancellation_reason(roomB)=="level exit")
        // A read-only view can bind a task without being able to cancel it.
        var inscope fresh <- cancellation_token()
        var inscope view <- cancellation_view(fresh)
        var inscope c <- task_spawn(runtime,task_with_cancellation(waiting_job(),view))
        task_tick(runtime,3)
        verify(task_status(c)==TaskStatus.Waiting)
        cancellation_cancel(fresh,"done")
        task_tick(runtime,4)
        verify(task_status(c)==TaskStatus.Cancelled && closed==before+3)
    }
}

[export]
def main() {
    checks();let baseline=heap_bytes_allocated()
    for(i in range(5)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task cancellation tree checks OK\n")
}
