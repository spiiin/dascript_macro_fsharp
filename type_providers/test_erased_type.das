options gen2
require erased_provider
[export]
def main() {
    var node : JsonValue?
    let health : string = erased(node, "schemas/world", "Player", _.health)
    print("{health}\n")
}
