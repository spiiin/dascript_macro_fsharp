options gen2
require ../examples/optics_model.das
[export]
def main() {
    var inscope player <- optics_player()
    let hp=player |> optic_get("stats.missing")
}
