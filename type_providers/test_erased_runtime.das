options gen2
require erased_provider
[export]
def main() {
    var error : string
    var node = read_json("\{\"health\":\"not a number\"\}", error)
    {
        // The selector is statically valid. Actual data violates its contract.
        let value = erased(node, "schemas/world", "Player", _.health)
        print("{value}\n")
    } finally { delete_json(node) }
}
