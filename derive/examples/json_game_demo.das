options gen2
require ./json_game_model.das
[export]
def main() {
    var inscope game <- derive_from_json(json_game_text(),type<JsonGame>,"game")
    verify(game.ok && game.value.players[0].level==1 && game.value.players[0].session==42)
    let text=derive_to_json(game.value)
    print("{text}\n")
    var inscope again <- derive_from_json(text,type<JsonGame>,"game")
    verify(again.ok && derive_equal(game.value,again.value))
    var inscope bad <- derive_from_json("\{\"players\":[\{\"displayName\":\"\",\"stats\":\{\"health\":-5,\"mana\":60\},\"tags\":[]\},\{\"displayName\":\"Bob\",\"stats\":\{\"health\":0,\"mana\":10\},\"tags\":[]\}],\"spawn\":[0,0]\}",type<JsonGame>,"game")
    verify(!bad.ok && length(bad.errors)==4)
    for(issue in bad.errors) {print("{issue.path}: {issue.message} [{issue.code}]\n")}
    print("Derive JSON game demo OK\n")
}
