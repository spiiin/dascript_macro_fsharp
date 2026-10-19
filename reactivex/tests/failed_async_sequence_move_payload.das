options gen2
require ../lib/reactivex_async_sequence.das
require ../../computation_expressions/lib/computation_macro.das
[export]
def main() {
    var inscope clock <- rx_virtual_scheduler()
    var source <- @() {return <- computation(AsyncSequenceBuilder(type<array<int>>)) {yield <- [1,2]}} |> rx_from_async_sequence(clock)
    delete source
}
