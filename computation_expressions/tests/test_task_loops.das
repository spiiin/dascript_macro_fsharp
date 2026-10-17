options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das
require daslib/rtti
var advanced=0
var closed=0
var disposed=0
var effects=0
def source() {
    return <- generator<int> {
        for(i in range(10)) {advanced++;yield i}
        return false
    } finally {closed++}
}
def checks() {
    advanced=0;closed=0;disposed=0;effects=0
    {
        var inscope task <- computation(TaskBuilder(type<int>)) {
            var total=0
            var data <- [1,2,3]
            for(i in [4,5,6]) {let n=task_after_polls(1,i) |> bind;total+=n}
            for(i in data) {let n=task_after_polls(1,i) |> bind;total+=n}
            return total+length(data)
        }
        while(task_poll(task)==TaskStatus.Waiting) {}
        verify(task_status(task)==TaskStatus.Succeeded && task_value(task)==24)
    }
    {
        var inscope task <- computation(TaskBuilder(type<int>)) {
            for(i in source()) {
                try_finally($ {
                    let n=task_after_polls(1,i) |> bind
                    if(n==1) {continue}
                    if(n==3) {break}
                    effects+=n+1
                },$ {disposed++})
            }
            return effects
        }
        while(task_poll(task)==TaskStatus.Waiting) {}
        verify(task_status(task)==TaskStatus.Succeeded && task_value(task)==4)
        verify(advanced==4 && disposed==4 && closed==1)
    }
    {
        var inscope task <- computation(TaskBuilder(type<int>)) {
            var total=0
            var i=0
            while(i<10) {
                i++
                task_after_polls(1,CeUnit()) |> bind
                if(i==2) {continue}
                if(i==4) {break}
                for(j,k in range(3),range(2)) {
                    if(j==1) {continue}
                    total+=i+k
                }
            }
            return total
        }
        while(task_poll(task)==TaskStatus.Waiting) {}
        verify(task_status(task)==TaskStatus.Succeeded && task_value(task)==4)
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(24)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("Task loop checks OK\n")
}
