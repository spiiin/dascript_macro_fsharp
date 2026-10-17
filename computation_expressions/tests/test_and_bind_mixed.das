options gen2
require ../lib/computation.das
[export]
def main() {
    let value = computation(ResultBuilder()) { let p = result_ok(1) |> and_bind(some(2)) |> bind; return p }
    print("{value}")
}
