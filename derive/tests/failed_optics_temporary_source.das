options gen2
require ../examples/optics_model.das
[export]
def main() {
    var inscope player <- optics_player()
    var inscope copy <- optics_player().stats |> optic_get("bonuses")
}
