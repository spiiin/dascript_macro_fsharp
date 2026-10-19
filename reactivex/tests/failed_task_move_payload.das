options gen2
options max_infer_passes=1024
require ../lib/reactivex_task.das
[export]
def main() {
    var inscope clock <- rx_virtual_scheduler()
    var inscope source <- rx_from_task(@(){
        var values:array<int>;values <- [1,2]
        return <- task_after_polls_move(1,values)
    },clock)
}
