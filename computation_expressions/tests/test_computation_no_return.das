options gen2
require ../lib/computation.das
[export]
def main() {
    let value = computation(ResultBuilder()) {
        result_ok(1) |> bind
    }
    assert(value is ok)
    print("no return: successful Unit OK\n")
}
