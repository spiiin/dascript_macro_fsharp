options gen2
require ../examples/optics_model.das
[export]
def main() {
    var inscope player <- optics_player()
    let path=optic("inventory[0]")
}
