options gen2
require ../lib/computation.das
[export]
def main() {
    let value = computation(ResultBuilder()) { let p = result_ok(1) |> and_bind(result_ok(2)); return p }
    print("{value}")
}
