options gen2
require ../examples/prism_model.das
[export]
def main() {
    var inscope player <- prism_player()
    var path="optional.some.health"
    var inscope found <- player |> prism_try_get(path)
}
