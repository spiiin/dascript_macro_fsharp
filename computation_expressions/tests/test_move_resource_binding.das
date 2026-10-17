options gen2
require ../support/move_resource_support.das
[export]
def main() {
    let result=computation(ResultBuilder()) {
        var buffer <- acquire_buffer(1) |> use_resource
        return 1
    }
}
