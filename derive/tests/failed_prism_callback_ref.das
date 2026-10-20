options gen2
require ../examples/prism_model.das
[export]
def main() {
    var inscope player <- prism_player()
    var inscope found <- player |> prism_over("optional.some.bonuses") <| $(values:array<int>) : array<int>& {unsafe {return values}}
}
