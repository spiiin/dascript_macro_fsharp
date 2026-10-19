options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
[export]
def main() {
    var inscope source <- rx_throw("failed",type<int>) |> rx_catch_error(@(s:string) {return <- rx_just("wrong payload type")})
}
