options gen2
require ../lib/computation.das
require daslib/rtti

def result_values() {
    var inscope values <- [7,8]
    return <- move_ok(values)
}

def option_values() {
    var inscope values <- [7,8]
    return <- move_some(values)
}

def exercise() {
    var cleaned=0
    let state=computation(StateBuilder(0)) {
        try_with($ {
            try_finally($ {
                state_put(12) |> bind
                panic("state")
                return 0
            }, $ {cleaned++})
        }, $(message:string) {
            let current=state_get() |> bind
            return current
        })
    }
    verify(state.value==12 && state.state==12 && cleaned==1)

    var inscope list <- computation(ListBuilder()) {
        try_with($ {yield 1;panic("list");yield 2}, $(message:string) {yield 7;yield 8})
    }
    verify(length(list)==2 && list[0]==7 && list[1]==8)

    var inscope result <- computation(MoveResultBuilder()) {
        try_with($ {
            panic("result")
            return result_values() |> return_from
        }, $(message:string) {return result_values() |> return_from})
    }
    verify(result is ok && length(result as ok)==2 && (result as ok)[1]==8)

    var inscope option <- computation(MoveOptionBuilder()) {
        try_with($ {
            panic("option")
            return option_values() |> return_from
        }, $(message:string) {return option_values() |> return_from})
    }
    verify(option is some && length(option as some)==2 && (option as some)[0]==7)

    var inscope owned <- computation(ListBuilder(type<array<int>>)) {
        try_with($ {panic("owned-list");yield <- [0]}, $(message:string) {yield <- [7,8]})
    }
    verify(length(owned)==1 && length(owned[0])==2 && owned[0][1]==8)
}

[export]
def main() {
    exercise()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {
        exercise()
        verify(heap_bytes_allocated()==baseline)
    }
    print("Recover portability checks OK\n")
}
