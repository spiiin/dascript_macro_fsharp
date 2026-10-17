options gen2
require json_provider
[json_provider(schema="schemas/player.json")]
struct Player {}
[export]
def main() {
    var p = Player()
    print("{p.healt}\n") // Intentional compile error: no such generated field.
}
