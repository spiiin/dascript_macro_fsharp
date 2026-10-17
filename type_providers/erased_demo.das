options gen2
require erased_provider
require daslib/fio

// The schema graph contains Player -> Team -> Player (a cycle).
// Broken, NotDownloaded and Player.future must stay unexpanded.

def read_once(var calls : int&; var node : JsonValue?) : JsonValue? {
    calls++
    return node
}

[export]
def main() {
    var error : string
    var node = read_json(fread("data/world.json"), error)
    {
        if (node == null) { panic(error) }
        let name : string = erased(node, "schemas/world", "Player", _.name)
        let health : int = erased(node, "schemas/world", "Player", _.health)
        let alive : bool = erased(node, "schemas/world", "Player", _.alive)
        let team : string = erased(node, "schemas/world", "Player", _.team.title)
        var calls = 0
        let leader : string = erased(read_once(calls, node), "schemas/world", "Player", _.team.leader.name)
        assert(calls == 1)
        assert(name == "Alice" && health == 100 && alive)
        assert(team == "Explorers" && leader == "Bob")

        // A virtual object result really is JsonValue?, without a proxy struct.
        var view : JsonValue? = erased(node, "schemas/world", "Player", _.team)
        let same_view = view == node?["team"]
        assert(same_view)
        print("{name}: {health}, alive={alive}\n")
        print("team={team}, leader={leader}, root evaluations={calls}\n")
        print("erased demo OK\n")
    } finally { delete_json(node) }
}
