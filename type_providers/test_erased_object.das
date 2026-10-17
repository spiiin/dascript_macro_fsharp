options gen2
require erased_provider
[export]
def main() {
    var error : string
    var node = read_json("\{\"team\":null\}", error)
    {
        let value = erased(node, "schemas/world", "Player", _.team.title)
        print("{value}\n")
    } finally { delete_json(node) }
}
