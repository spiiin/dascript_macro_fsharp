options gen2
require native_functions
require lazy_native_provider
require daslib/fio

// Different spelling of the same canonical path must give the SAME nominal type.
typedef LocalPlayer = provided_type("schemas/native/../native", "Player")

[export]
def main() {
    var player = default<LocalPlayer>
    var error : string
    if (!try_load_native(fread("data/native_player.json"), player, error)) { panic(error) }
    // The loader has already freed its JSON tree. Everything below uses native fields.
    apply_damage(player, 10)
    let team = get_team(player)
    let description = describe_team(team)
    assert(player.health == 90 && team.leader_id == 42)
    print("{player.name}: health={player.health}; {description}\n")
    print("native demo OK\n")
}
