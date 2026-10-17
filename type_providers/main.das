options gen2
require json_provider
require daslib/fio

// No hand-written fields: the compiler gets them from the external schema.
[json_provider(schema="schemas/player.json")]
struct Player {}

[export]
def main() {
    var player = Player()
    var error : string
    if (!try_parse_Player(fread("data/player.json"), player, error)) { panic(error) }
    assert(player.name == "Alice" && player.health == 100 && player.alive)
    print("{player.name}: health={player.health}, alive={player.alive}\n")
    player.health -= 10
    print("after damage: {player.health}\n")

    // A bad payload fails at runtime, leaving the previous result intact.
    let bad = "\{\"name\":\"Bob\",\"health\":\"oops\",\"alive\":true\}"
    let accepted = try_parse_Player(bad, player, error)
    assert(!accepted)
    assert(player.name == "Alice" && player.health == 90)
    print("rejected: {error}\n")
    print("OK\n")
}
