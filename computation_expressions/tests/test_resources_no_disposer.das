options gen2
require ../lib/computation.das
struct NoDisposer { id : int }
[export]
def main() {
    let bad = computation(ResultBuilder()) {
        let owned = NoDisposer(id=1) |> use_resource
        return owned.id
    }
    print("{bad}\n")
}
