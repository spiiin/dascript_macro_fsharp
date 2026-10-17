options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das
require daslib/strings_boost
require daslib/rtti
var opened=0
var closed=0
var callbacks=0
var polls=0
var externalReady=false
struct Resource {id:int}
struct Buffer {values:array<int>}
def acquire() {opened++;return Resource(id=opened)}
def ce_dispose(value:Resource) {closed++}
def acquire_buffer() {opened++;return <- Buffer(values <- [1,2,3])}
def ce_dispose(var value:Buffer) {closed++;delete value}
def buffered_task() {
    return <- computation(TaskBuilder(type<int>)) {
        var resource & = acquire_buffer() |> use_resource
        let n=task_after_polls(1,4) |> bind
        resource.values |> push(n)
        return length(resource.values)
    }
}
def owned_task(fail:bool) {
    return <- computation(TaskBuilder(type<int>)) {
        let resource=acquire() |> use_resource
        let n=task_after_polls(1,42) |> bind
        if(fail) {panic("body failed")}
        return n
    }
}
def external() {
    return <- task_from_poll(@() {
        polls++
        return externalReady ? task_ready(9) : task_pending(type<int>)
    },@() {callbacks++})
}
def captured_callback(value:string) {
    return <- task_from_poll(@() {return task_ready(value)},@() {})
}
def check_resources() {
    {
        var snapshotName="before"
        var inscope task <- captured_callback(snapshotName)
        snapshotName="after"
        verify(task_poll(task)==TaskStatus.Succeeded && task_value(task)=="before")
    }
    {
        var inscope task <- buffered_task()
        verify(task_poll(task)==TaskStatus.Waiting && opened==closed+1)
        verify(task_cancel(task) && opened==closed)
    }
    {
        var inscope task <- buffered_task()
        verify(task_poll(task)==TaskStatus.Waiting)
        verify(task_poll(task)==TaskStatus.Succeeded && task_value(task)==4 && opened==closed)
    }
    {
        var inscope never <- owned_task(false)
        verify(task_cancel(never) && opened==closed)
        verify(task_status(never)==TaskStatus.Cancelled)
    }
    {
        var inscope waiting <- owned_task(false)
        verify(task_poll(waiting)==TaskStatus.Waiting && opened==closed+1)
        verify(task_cancel(waiting) && opened==closed)
        verify(!task_cancel(waiting))
        verify(task_poll(waiting)==TaskStatus.Cancelled)
    }
    {
        var inscope failed <- owned_task(true)
        verify(task_poll(failed)==TaskStatus.Waiting)
        verify(task_poll(failed)==TaskStatus.Failed && opened==closed)
        verify(starts_with(task_error(failed),"body failed"))
    }
    {
        var inscope good <- owned_task(false)
        verify(task_poll(good)==TaskStatus.Waiting)
        verify(task_poll(good)==TaskStatus.Succeeded && opened==closed)
    }
    {
        var inscope parent <- computation(TaskBuilder(type<int>)) {
            let x=owned_task(false) |> bind
            return x+1
        }
        verify(task_poll(parent)==TaskStatus.Waiting && opened==closed+1)
        verify(task_cancel(parent) && opened==closed)
    }
}
[export]
def main() {
    check_resources()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check_resources()}
    verify(heap_bytes_allocated()==baseline)
    {
        var inscope operation <- external()
        verify(polls==0 && callbacks==0)
        verify(task_poll(operation)==TaskStatus.Waiting && polls==1 && callbacks==0)
        externalReady=true
        verify(task_poll(operation)==TaskStatus.Succeeded && polls==2 && callbacks==1)
        verify(task_value(operation)==9)
    }
    {
        var inscope operation <- external()
        verify(task_cancel(operation) && callbacks==2 && polls==2)
    }
    var task <- owned_task(false)
    var caught=false
    try {
        task_scope(task,$(var owner) {
            verify(task_poll(owner)==TaskStatus.Waiting)
            panic("driver failed")
        })
    } recover {caught=true}
    verify(caught && opened==closed)
    {
        var inscope fault <- task_from_poll(@() : tuple<tag:TaskEventTag;ready:bool;value:int> {
            panic("poll failed")
            return task_ready(0)
        },@() {callbacks++})
        verify(task_poll(fault)==TaskStatus.Failed && callbacks==3)
        verify(starts_with(task_error(fault),"poll failed"))
    }
    {
        var inscope fault <- task_from_poll(@() {return task_pending(type<int>)},@() {callbacks++;panic("close failed")})
        verify(task_poll(fault)==TaskStatus.Waiting)
        verify(task_cancel(fault) && task_status(fault)==TaskStatus.Failed && callbacks==4)
        verify(starts_with(task_error(fault),"close failed"))
    }
    print("Task lifetime checks OK\n")
}
