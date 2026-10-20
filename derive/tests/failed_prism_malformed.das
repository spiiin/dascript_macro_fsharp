options gen2
require ../examples/prism_model.das
[export]
def main() {
    var inscope player <- prism_player()
    let path=prism("optional..some")
}
