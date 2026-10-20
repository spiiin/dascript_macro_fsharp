options gen2
require ../examples/prism_model.das
[export]
def main() {
    var inscope player <- prism_player()
    let found=42 |> prism_matches("some")
}
