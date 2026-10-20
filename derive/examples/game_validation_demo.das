options gen2
require ./validation_model.das
[export]
def main() {
    var inscope config <- invalid_game_config()
    var inscope errors <- derive_validate(config,"game")
    verify(length(errors)==6 && validation_custom_calls==2)
    for(issue in errors) {print("{issue.path}: {issue.message} [{issue.code}]\n")}
    print("Derive game validation demo OK\n")
}
