options gen2
require ../examples/prism_model.das
[export]
def main() {
    var inscope player <- prism_player()
    var inscope found <- prism_try_get(player)
}
