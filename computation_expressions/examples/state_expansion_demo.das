options gen2
require ../lib/computation.das
[export]
def main() {
    let result=computation(StateBuilder(5)) {
        for (i in range(16)) {
            let state=state_get() |> bind
            state_put(state+i) |> bind
        }
        let state=state_get() |> bind
        return state*2
    }
    print("{result}\n")
}
