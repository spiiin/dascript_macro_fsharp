options gen2
require ../examples/validation_model.das
require daslib/rtti
[derive(validate=true)]
struct FixedParty {members:ValidatedStats[2]}
[derive(validate=true)]
struct Matrix {rows:array<array<ValidatedStats>>}

def detached_errors() {
    var inscope config <- invalid_game_config()
    return <- derive_validate(config,"snapshot")
}

def check() {
    validation_custom_calls=0
    var inscope config <- invalid_game_config()
    var inscope errors <- derive_validate(config,"game")
    verify(length(errors)==6 && validation_custom_calls==2)
    verify(errors[0].path=="game.players[0].name" && errors[0].code=="non_empty")
    verify(errors[1].path=="game.players[0].name" && errors[1].code=="min_length")
    verify(errors[2].path=="game.players[0].stats.health" && errors[2].code=="min")
    verify(errors[3].path=="game.players[0].stats.mana" && errors[3].code=="max")
    verify(errors[4].path=="game.players[0].skills" && errors[4].code=="max_length")
    verify(errors[5].path=="game.players[1].stats.mana" && errors[5].code=="custom")
    verify(config.players[0].stats.health==-10 && length(config.players[0].skills)==3)
    // Existing output is retained by the low-level append API.
    var inscope appended:array<ValidationIssue>
    validation_add(appended,"manual","already present")
    derive_validate_into(config,"",appended)
    verify(length(appended)==7 && appended[0].path=="manual" && appended[1].path=="players[0].name")
    var inscope direct <- derive_validate(config.players,"players")
    verify(length(direct)==6 && direct[0].path=="players[0].name")
    var inscope partyErrors <- derive_validate(FixedParty(members=fixed_array(ValidatedStats(health=101,mana=0),ValidatedStats(health=1,mana=-1))))
    verify(length(partyErrors)==2 && partyErrors[0].path=="members[0].health" && partyErrors[1].path=="members[1].mana")
    var inscope matrix:Matrix
    var inscope row:array<ValidatedStats>
    row |> push(ValidatedStats(health=-1,mana=0))
    matrix.rows |> emplace(row)
    var inscope matrixErrors <- derive_validate(matrix)
    verify(length(matrixErrors)==1 && matrixErrors[0].path=="rows[0][0].health")
    // Boundaries accepted, custom hooks still run on valid data.
    var inscope ok <- derive_validate(ValidatedStats(health=100,mana=50))
    verify(length(ok)==0)
    var inscope empty:GameConfig
    var inscope emptyErrors <- derive_validate(empty)
    verify(length(emptyErrors)==1 && emptyErrors[0].path=="players")
    config.players[0].name="Alice"
    config.players[0].stats=ValidatedStats(health=1,mana=50)
    config.players[0].skills.resize(2)
    config.players[1].stats.mana=0
    var inscope fixed <- derive_validate(config)
    verify(length(fixed)==0)
    // Returned issues outlive all input containers.
    var inscope detached <- detached_errors()
    verify(length(detached)==6 && detached[5].path=="snapshot.players[1].stats.mana")
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive validation checks OK\n")
}
