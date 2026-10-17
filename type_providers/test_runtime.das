options gen2
require json_provider
require strings

[json_provider(schema="schemas/player.json")]
struct Player {}

def reject(text : string; expected : string) {
    var p = Player(name="unchanged", health=7, alive=true)
    var error : string
    let ok = try_parse_Player(text, p, error)
    assert(!ok)
    assert(!empty(error))
    assert(empty(expected) || find(error, expected) >= 0)
    assert(p.name == "unchanged" && p.health == 7 && p.alive)
}

[export]
def main() {
    reject("[]", "expected JSON object")
    reject("not json", "")
    reject("\{\}", "name")
    reject("\{\"name\":null\}", "name")
    reject("\{\"name\":\"Bob\",\"health\":1.5,\"alive\":true\}", "integer")
    reject("\{\"name\":\"Bob\",\"health\":2147483648,\"alive\":true\}", "int32")
    reject("\{\"name\":\"Bob\",\"health\":-2147483649,\"alive\":true\}", "int32")
    reject("\{\"name\":\"Bob\",\"health\":10,\"alive\":1\}", "boolean")
    var p = Player()
    var error = "old error"
    let ok = try_parse_Player("\{\"name\":\"Bob\",\"health\":-2147483648,\"alive\":false,\"extra\":42\}", p, error)
    assert(ok && empty(error) && p.health == int(-2147483648l) && !p.alive)
    let max_ok = try_parse_Player("\{\"name\":\"Max\",\"health\":2147483647,\"alive\":true\}", p, error)
    assert(max_ok && p.health == 2147483647)
    print("runtime checks OK\n")
}
