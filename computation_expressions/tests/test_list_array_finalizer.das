options gen2
require ../lib/computation.das
require daslib/rtti
var frees=0
def finalize(var value:array<int>) {frees++; __builtin_array_free(value,typeinfo sizeof(type<int>))}
[export]
def main() {
    let baseline=heap_bytes_allocated()
    assert(!(typeinfo ce_has_collect_sink(ce_collect_sink(ListBuilder()))))
    {var inscope values <- computation(ListBuilder()) {
        let a=fixed_array(1,2) |> bind
        let unused=0
        let b=fixed_array(3,4) |> bind
        return a+b
    }}
    let before=frees;frees=0
    {var inscope values <- computation(ListBuilder()) {
        let a=fixed_array(1,2) |> bind
        let b=fixed_array(3,4) |> bind
        return a+b
    }}
    assert(before==frees)
    let current=heap_bytes_allocated();assert(current==baseline)
    print("List custom array finalizer checks OK\n")
}
