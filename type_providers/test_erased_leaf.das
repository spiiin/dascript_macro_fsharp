options gen2
require erased_provider
[export]
def main() {
    var error : string
    var node = read_json("\{\"absent\":\{\}\}", error)
    {
        // Reading the ref itself does not require downloading the target schema.
        var view : JsonValue? = erased(node, "schemas/world", "Player", _.absent)
        let same = view == node?["absent"]
        assert(same)
        print("lazy ref leaf OK\n")
    } finally { delete_json(node) }
}
