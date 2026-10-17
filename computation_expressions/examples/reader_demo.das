options gen2
require ../lib/computation_macro.das
require ../lib/reader_builder.das
require math

struct GameRules {
    damageMultiplier : int = 3
    armor : int = 4
}
def attack_damage(rules : GameRules; baseDamage : int) {
    return computation(ReaderBuilder(rules)) {
        let config = reader_ask() |> bind
        return max(0, baseDamage * config.damageMultiplier - config.armor)
    }
}
[export]
def main() {
    let rules = GameRules()
    let turn = computation(ReaderBuilder(rules)) {
        let damage = attack_damage(rules, 10) |> bind
        let config = reader_ask() |> bind
        return damage + config.armor
    }
    assert(turn.value == 30)
    print("reader demo OK: damage={turn.value}\n")
}
