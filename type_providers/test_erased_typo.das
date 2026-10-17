options gen2
require erased_provider
[export]
def main() {
    var node : JsonValue?
    let name = erased(node, "schemas/world", "Player", _.team.leader.naem)
    print("{name}\n")
}
