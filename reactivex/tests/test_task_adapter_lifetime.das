options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex_task.das
require ../../computation_expressions/lib/task_scheduler.das
require daslib/rtti
var opened=0
var freed=0
var closed=0
var errors=0
var completed=0
var callbacksFreed=0
var polling=false
var active:RxSubscription
struct Hold {
    data:array<int>
    def finalize {if(!empty(data)) {freed++;delete data}}
}
def hold() {opened++;return <- Hold(data <- [42])}
def tracked(source:auto) {
    var view <- rx_clone(source)
    return <- rx_defer(@ capture(<-view) () {
        var data <- hold()
        return <- rx_clone(view) |> rx_map(@ capture(<-data) (n:int) {verify(data.data[0]==42);return n} finally {delete data})
    } finally {delete view})
}
def work(mode:int) {
    var data <- hold()
    var remaining=2
    return <- task_from_poll(@ capture(copy(mode),copy(remaining)) () {
        if(mode==4 || mode==9) {panic("poll failed")}
        if(mode==7) {
            polling=true
            let before=closed
            rx_unsubscribe(active)
            verify(before==closed) // cancellation must not destroy this frame.
            polling=false
        }
        if(mode==1 || mode==2 || mode==3 || mode==6 || mode==7 || mode==8) {return task_pending(type<int>)}
        if(remaining>0) {remaining--;return task_pending(type<int>)}
        return task_ready(77)
    },@ capture(<-data,copy(mode)) () {
        verify(!polling && data.data[0]==42);closed++
        if(mode==6) {panic("close failed")}
    } finally {delete data})
}
def checks() {
    for(mode in range(10)) {
        let before=closed
        let oldErrors=errors
        let oldDone=completed
        let oldCallbacks=callbacksFreed
        var inscope clock <- rx_virtual_scheduler()
        var factoryData <- hold()
        var source <- rx_from_task(@ capture(<-factoryData,copy(mode)) () {
            verify(factoryData.data[0]==42)
            if(mode==8) {rx_unsubscribe(active)} // cancellation during creation.
            return <- work(mode)
        } finally {delete factoryData},clock) |> rx_timeout(5,clock)
        var callbackData <- hold()
        active <- rx_subscription()
        rx_subscribe_with(active,source,@ capture(<-callbackData,copy(mode)) (n:int) {
            verify(callbackData.data[0]==42 && n==77)
            if(mode==5) {panic("observer failed")}
        } finally {delete callbackData;callbacksFreed++},@ capture(copy(mode)) (s:string) {errors++;if(mode==9) {panic("error callback failed")}},@(){completed++})
        delete source
        var caught=false
        try {
            if(mode==3) {rx_scheduler_close(clock)}
            elif(mode==1 || mode==6) {rx_advance_to(clock,0);rx_unsubscribe(active)}
            elif(mode==2) {rx_advance_to(clock,10)}
            else {rx_advance_to(clock,10)}
        } recover {caught=true}
        verify(caught==(mode==5 || mode==6 || mode==9))
        verify(rx_is_closed(active) && rx_pending_count(clock)==0 && rx_close_listener_count(clock)==0 && closed==before+1)
        delete active
        verify(opened==freed && callbacksFreed==oldCallbacks+1)
        verify(errors==oldErrors+((mode==2 || mode==3 || mode==4 || mode==9) ? 1 : 0))
        verify(completed==oldDone+(mode==0 ? 1 : 0))
    }
    // Rx->Task retains a descriptor but releases the active source connection
    // on its first next, error, empty completion, cancellation, or Task timeout.
    for(mode in range(6)) {
        var inscope input <- rx_subject(type<int>)
        var source <- tracked(input)
        var task <- rx_first_task(source)
        delete source
        if(mode==0) {task_cancel(task)}
        elif(mode==5) {
            var inscope scheduler <- task_scheduler(type<$Result<int;string>>)
            let id=task_spawn(scheduler,task,TaskTimeout(after_ms=5))
            task_tick(scheduler,0);verify(rx_subscriber_count(input)==1)
            task_tick(scheduler,5)
            verify(task_status(scheduler,id)==TaskStatus.Cancelled && rx_subscriber_count(input)==0)
        } else {
            verify(task_poll(task)==TaskStatus.Waiting && rx_subscriber_count(input)==1)
            if(mode==1) {rx_subject_next(input,42)}
            elif(mode==2) {rx_subject_complete(input)}
            elif(mode==3) {rx_subject_error(input,"source failed")}
            else {task_cancel(task)}
            if(mode!=4) {verify(task_poll(task)==TaskStatus.Succeeded)}
        }
        delete task
        verify(rx_subscriber_count(input)==0 && opened==freed)
    }
    {
        var inscope input <- rx_subject(type<int>)
        var inscope source <- tracked(input)
        var inscope first <- rx_first_task(source)
        var inscope second <- rx_first_task(source)
        task_poll(first);task_poll(second)
        verify(rx_subscriber_count(input)==2)
        task_cancel(first);verify(rx_subscriber_count(input)==1)
        rx_subject_next(input,7);task_poll(second)
        verify(rx_subscriber_count(input)==0 && opened==freed)
    }
    // The factory is invoked, but its Task is closed before its first poll if
    // subscription is attempted on an already closed scheduler.
    for(fail in range(2)) {
        var inscope clock <- rx_virtual_scheduler()
        rx_scheduler_close(clock)
        var inscope source <- rx_from_task(@(){return <- work(0)},clock)
        let before=closed
        var caught=false
        try {
            var inscope sub <- rx_subscribe(source,@(n:int) {panic("unexpected next")},@ capture(copy(fail)) (s:string) {
                verify(s=="rx scheduler closed");if(fail==1) {panic("closed callback failed")}
            },@(){panic("unexpected complete")})
            verify(rx_is_closed(sub))
        } recover {caught=true}
        verify(caught==(fail==1) && closed==before+1 && opened==freed && rx_close_listener_count(clock)==0)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX Task adapter lifetime checks OK\n")
}
