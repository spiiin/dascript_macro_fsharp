options gen2
module native_functions public
require lazy_native_provider public

typedef Player = provided_type("schemas/native", "Player")
typedef Team = provided_type("schemas/native", "Team")

def apply_damage(var player : Player; damage : int) {
    player.health -= damage
}

def get_team(player : Player) : Team {
    return player.team
}

def describe_team(team : Team) : string {
    return "{team.title}, leader #{team.leader_id}"
}
