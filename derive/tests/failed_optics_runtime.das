options gen2
require ../examples/optics_model.das
[export]
def main() {
    var inscope player <- optics_player()
    var path="stats.health"
    let hp=player |> optic_get(path)
}
