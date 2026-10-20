options gen2
require ../examples/optics_model.das
[export]
def main() {
    var inscope player <- optics_player()
    var inscope copy <- player |> optic_over("inventory") <| $(values:array<int>) : array<int>& {unsafe {return values}}
}
