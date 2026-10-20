options gen2
require ../examples/json_game_model.das
require daslib/rtti
require strings

def detached_game() {
    var text=json_game_text()
    return <- derive_from_json(text,type<JsonGame>,"game")
}
def check() {
    json_hook_calls=0
    var inscope game <- detached_game()
    verify(game.ok && json_hook_calls==1)
    verify(game.value.players[0].note=="no note" && game.value.players[0].session==42 && game.value.players[0].level==1)
    verify(game.value.players[0].tags[1]=="ёж")
    let encoded=derive_to_json(game.value)
    verify(find(encoded,"session")<0 && find(encoded,"displayName")>=0)
    var inscope again <- derive_from_json(encoded,type<JsonGame>)
    verify(again.ok && derive_equal(game.value,again.value))
    // All independent structural failures are retained; hooks do not run.
    json_hook_calls=0
    var inscope bad <- derive_from_json("\{\"players\":[\{\"displayName\":3,\"stats\":\{\"health\":2147483648,\"mana\":\"x\"\},\"tags\":[1,2]\}],\"spawn\":[0]\}",type<JsonGame>,"game")
    verify(!bad.ok && length(bad.errors)==6 && json_hook_calls==0)
    verify(bad.errors[0].path=="game.players[0].displayName" && bad.errors[0].code=="json_type")
    verify(bad.errors[1].path=="game.players[0].stats.health" && bad.errors[1].code=="json_range")
    verify(bad.errors[3].path=="game.players[0].tags[0]" && bad.errors[5].code=="json_length")
    verify(length(bad.value.players)==0) // No partially decoded value escapes.
    var inscope missing <- derive_from_json("\{\}",type<JsonGame>,"game")
    verify(length(missing.errors)==2 && missing.errors[0].code=="json_missing" && missing.errors[1].path=="game.spawn")
    var inscope invalid <- derive_from_json("\{\"players\":[\{\"displayName\":\"\",\"stats\":\{\"health\":0,\"mana\":1\},\"level\":0,\"tags\":[]\}],\"spawn\":[0,0]\}",type<JsonGame>,"game")
    verify(!invalid.ok && length(invalid.errors)==3)
    verify(invalid.errors[0].path=="game.players[0].displayName" && invalid.errors[1].code=="dead_player_mana" && invalid.errors[2].code=="min")
    var inscope rootArray <- derive_from_json("[\{\"health\":-1,\"mana\":0\}]",type<array<JsonStats>>)
    verify(!rootArray.ok && rootArray.errors[0].path=="[0].health")
    // Extra keys are ignored. Present optional null is still a type error.
    var inscope optionalNull <- derive_from_json("\{\"displayName\":\"A\",\"stats\":\{\"health\":1,\"mana\":0\},\"note\":null,\"tags\":[],\"unknown\":true\}",type<JsonPlayer>)
    verify(!optionalNull.ok && length(optionalNull.errors)==1 && optionalNull.errors[0].path=="note")
    // Default native JSON options must not silently drop empty arrays.
    let previous=set_no_empty_arrays(true)
    var inscope withEmpty <- derive_from_json("\{\"displayName\":\"A\",\"stats\":\{\"health\":1,\"mana\":0\},\"tags\":[]\}",type<JsonPlayer>)
    let emptyText=derive_to_json(withEmpty.value)
    verify(find(emptyText,"tags")>=0)
    verify(set_no_empty_arrays(previous))
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive JSON checks OK\n")
}
