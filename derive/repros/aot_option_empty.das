options gen2
require daslib/option
struct EmptyPayload {}
[export]
def main() {
    let value=some(EmptyPayload())
    verify(value is some)
    print("SDK empty Option interpreter/JIT OK\n")
}
