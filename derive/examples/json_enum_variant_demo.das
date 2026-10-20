options gen2
require ../lib/derive.das
enum Role {
Warrior
Mage
Rogue
}
[derive(json=true,validate=true)]
struct Move {
    @validate_min=0
    x:int
    y:int
}
variant Action {idle;move:Move;say:string;items:array<int>}
[derive(json=true,validate=true)]
struct Player {role:Role;action:Action}
[export]
def main() {
    var inscope player <- derive_from_json("\{\"role\":\"Mage\",\"action\":\{\"case\":\"move\",\"value\":\{\"x\":3,\"y\":4\}\}\}",type<Player>,"player",true)
    verify(player.ok && player.value.role==Role.Mage && player.value.action is move)
    print("{derive_to_json(player.value)}\n")
    var inscope again <- derive_from_json(derive_to_json(player.value),type<Player>,"player",true)
    verify(again.ok && derive_equal(player.value,again.value) && derive_hash(player.value)==derive_hash(again.value))
    var inscope idle <- derive_from_json("\{\"case\":\"idle\"\}",type<Action>,"action",true)
    verify(idle.ok && idle.value is idle)
    print("{derive_to_json(idle.value)}\n")
    print("Derive JSON enum variant demo OK\n")
}
