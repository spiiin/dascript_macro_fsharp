options gen2
require erased_provider
[export]
def main() {
    var node : JsonValue?
    let value = erased(node, "schemas/world", "Player", _.health.name)
    print("{value}\n")
}
