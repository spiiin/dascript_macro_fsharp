options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das
require daslib/strings_boost
var effects=0
var closes=0

def finished(var task:auto) {
    var state=task_poll(task)
    while(state==TaskStatus.Waiting) {state=task_poll(task)}
    verify(state==TaskStatus.Succeeded)
}
def string_task(prefix:string) {
    return <- computation(TaskBuilder(type<string>)) {
        let suffix=task_after_polls(1,"world") |> bind
        return "{prefix}, {suffix}"
    }
}
[export]
def main() {
    var inscope loop <- computation(TaskBuilder(type<int>)) {
        var total=0
        for(i in range(3)) {
            let n=task_after_polls(1,i) |> bind
            total+=n
        }
        while(total<5) {task_after_polls(1,CeUnit()) |> bind;total++}
        if(total==5) {return total} else {return -1}
    }
    finished(loop)
    verify(task_value(loop)==5)
    var inscope zipped <- computation(TaskBuilder(type<int>)) {
        var total=0
        for(i,j in range(3),range(2)) {let n=task_after_polls(1,i+j) |> bind;total+=n}
        return total
    }
    finished(zipped)
    verify(task_value(zipped)==2)
    var inscope immediate <- computation(TaskBuilder(type<int>)) {
        let a=task_after_polls(0,10) |> bind
        let b=task_after_polls(0,20) |> bind
        return a+b
    }
    verify(task_poll(immediate)==TaskStatus.Succeeded && task_value(immediate)==30)
    var inscope text <- string_task("hello")
    finished(text)
    verify(task_value(text)=="hello, world")
    var inscope early <- computation(TaskBuilder(type<int>)) {
        for(i in range(5)) {
            let n=task_after_polls(1,i) |> bind
            if(n==2) {return n}
            effects++
        }
        return -1
    }
    finished(early)
    verify(task_value(early)==2 && effects==2)
    var inscope missing <- computation(TaskBuilder(type<int>)) {let n=task_after_polls(0,3) |> bind}
    verify(task_poll(missing)==TaskStatus.Failed)
    verify(starts_with(task_error(missing),"task: computation ended without return"))
    var inscope scoped <- computation(TaskBuilder(type<int>)) {
        try_finally($ {
            let n=task_after_polls(1,7) |> bind
            return n
        },$ {closes++})
    }
    finished(scoped)
    verify(task_value(scoped)==7 && closes==1)
    var inscope recovered <- computation(TaskBuilder(type<int>)) {
        try_with($ {
            task_after_polls(1,0) |> bind
            panic("recover me")
            return 1
        },$(message:string) {return 9})
    }
    finished(recovered)
    verify(task_value(recovered)==9)
    print("Task control checks OK\n")
}
