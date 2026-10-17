options gen2
require ../lib/computation_macro.das
require ../lib/reader_result_builder.das

struct CombatRules {
    minimumLevel:int=3
    damageMultiplier:int=2
}

def attack(rules:CombatRules; level,baseDamage:int) {
    return computation(ReaderResultBuilder(rules)) {
        let config=reader_ask() |> bind
        if (level<config.minimumLevel) {
            result_error("Level too low",type<CeUnit>) |> bind
        }
        return baseDamage*config.damageMultiplier
    }
}

[export]
def main() {
    let rules=CombatRules()
    let turn=computation(ReaderResultBuilder(rules)) {
        let config=reader_ask() |> bind
        let first=attack(config,5,10) |> bind
        let second=attack(config,4,7) |> bind
        return first+second
    }
    assert(turn is ok && turn as ok==34)
    var reached=false
    let rejected=computation(ReaderResultBuilder(rules)) {
        let damage=attack(rules,1,10) |> bind
        reached=true
        return damage
    }
    assert(rejected is error && !reached)
    print("Damage: {turn as ok}; rejected: {rejected as error}\n")
    print("reader/result demo OK\n")
}
