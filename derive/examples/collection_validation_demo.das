options gen2
require ./collection_validation_model.das
[export]
def main() {
    var inscope roster <- invalid_roster()
    var inscope issues <- derive_validate(roster,"game")
    verify(length(issues)==10)
    for(issue in issues) {print("{issue.path}: [{issue.code}] {issue.message}\n")}
    print("Derive collection validation demo OK\n")
}
