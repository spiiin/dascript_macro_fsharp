options gen2
require ../lib/computation_macro.das
require ../lib/task_builder.das
require daslib/async_boost

[async]
def standard_name() : string {
    await_next_frame()
    yield "Alice"
}
[async]
def standard_health(allowed:bool) : $Result<int;string> {
    await_next_frame()
    yield allowed ? result_ok(85) : result_error("access denied",type<int>)
}
[export]
def main() {
    var inscope greeting <- computation(TaskBuilder(type<string>)) {
        let name=task_from_async(standard_name()) |> bind
        return "Hello, {name}"
    }
    verify(task_poll(greeting)==TaskStatus.Waiting)
    verify(task_poll(greeting)==TaskStatus.Succeeded)
    print("{task_value(greeting)}\n")
    var inscope rejected <- computation(TaskResultBuilder(type<int>)) {
        let health=task_from_async(standard_health(false)) |> bind
        print("This step will not run\n")
        return health+10
    }
    verify(task_poll(rejected)==TaskStatus.Waiting)
    verify(task_poll(rejected)==TaskStatus.Succeeded)
    let result=task_value(rejected)
    verify(result is err)
    print("{result as err}\nTask async demo OK\n")
}
