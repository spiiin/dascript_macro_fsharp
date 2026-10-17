options gen2
require ../lib/computation.das
[export]
def main() {
    let bad = computation(ResultBuilder()) { 42 |> use_resource }
    print("{bad}\n")
}
