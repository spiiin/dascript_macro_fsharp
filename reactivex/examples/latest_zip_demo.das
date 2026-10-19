options gen2
options max_infer_passes=1024
require ../lib/reactivex.das
[export]
def main() {
    var inscope temperature <- rx_subject(type<int>)
    var inscope location <- rx_subject(type<string>)
    var inscope latest <- rx_clone(temperature) |> rx_combine_latest(rx_clone(location))
    var inscope pairs <- rx_clone(temperature) |> rx_zip(rx_clone(location))
    var inscope a <- rx_subscribe(latest,@(v:tuple<first:int;second:string>) {print("latest: {v.first} {v.second}\n")},
        @(message:string) {panic(message)},@(){print("latest done\n")})
    var inscope b <- rx_subscribe(pairs,@(v:tuple<first:int;second:string>) {print("zip: {v.first} {v.second}\n")},
        @(message:string) {panic(message)},@(){print("zip done\n")})
    rx_subject_next(temperature,20)
    rx_subject_next(temperature,21)
    rx_subject_next(location,"outside")
    rx_subject_next(location,"inside")
    rx_subject_complete(temperature)
    rx_subject_next(location,"office")
    rx_subject_complete(location)
    print("ReactiveX combine_latest/zip demo OK\n")
}
