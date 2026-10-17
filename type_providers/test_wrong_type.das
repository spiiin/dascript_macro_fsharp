options gen2
require json_provider
[json_provider(schema="schemas/player.json")]
struct Player {}
[export]
def main() {
    var p = Player()
    p.health = "oops" // Intentional compile error: health is int.
}
