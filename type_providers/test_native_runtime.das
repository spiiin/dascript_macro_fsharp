options gen2
require native_functions
require lazy_native_provider
require strings

def reject(text, expected : string) {
    var value = default<Player>
    value.name = "preserved"
    value.health = 77
    value.team.title = "old team"
    value.team.leader_id = 5
    var error : string
    let ok = try_load_native(text, value, error)
    assert(!ok && !empty(error))
    assert(find(error, expected) >= 0)
    assert(value.name == "preserved" && value.health == 77)
    assert(value.team.title == "old team" && value.team.leader_id == 5)
}

[export]
def main() {
    reject("[]", "$: expected object")
    reject("\{\}", "$.name")
    reject("\{\"name\":\"Bob\",\"health\":2147483648\}", "$.health")
    reject("\{\"name\":\"Bob\",\"health\":1,\"alive\":true,\"team\":null\}", "$.team")
    reject("\{\"name\":\"Bob\",\"health\":1,\"alive\":true,\"team\":\{\"title\":\"New\"\}\}", "$.team.leader_id")
    reject("\{\"name\":\"Bob\",\"health\":1,\"alive\":true,\"team\":\{\"title\":\"New\",\"leader_id\":\"bad\"\}\}", "$.team.leader_id")
    var value = default<Player>
    var error = "old error"
    let loaded = try_load_native("\{\"name\":\"Bob\",\"health\":1,\"alive\":false,\"team\":\{\"title\":\"New\",\"leader_id\":5\}\}", value, error)
    assert(loaded && empty(error))
    var copy = value
    apply_damage(copy, 1)
    copy.team.leader_id = 6
    assert(value.health == 1 && value.team.leader_id == 5)
    assert(copy.health == 0 && copy.team.leader_id == 6)
    let team = get_team(value)
    let description = describe_team(team)
    assert(description == "New, leader #5")
    print("native runtime OK\n")
}
