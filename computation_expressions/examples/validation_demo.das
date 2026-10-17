options gen2
require ../lib/computation_macro.das
require ../lib/validation_builder.das

struct Character { name:string; level:int }
def check_name(name:string) {
    if (empty(name)) { return validation_error("Name must not be empty", type<string>) }
    return validation_ok(name)
}
def check_level(level:int) {
    if (level < 1 || level > 100) { return validation_error("Level must be between 1 and 100", type<int>) }
    return validation_ok(level)
}
def create_character(name:string; level:int) {
    return computation(ValidationBuilder()) {
        // Explicit statements guarantee each check runs once in this order.
        let checkedName = check_name(name)
        let checkedLevel = check_level(level)
        let fields = checkedName |> validation_zip(checkedLevel) |> bind
        return Character(name=fields.first, level=fields.second)
    }
}
[export]
def main() {
    let rejected = create_character("", 0)
    assert(rejected is invalid && (rejected as invalid).count == 2)
    print("{(rejected as invalid).messages}\n")
    let accepted = create_character("Mage", 12)
    assert(accepted is valid && (accepted as valid).level == 12)
    print("validation demo OK\n")
}
