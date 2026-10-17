options gen2
require native_functions
require lazy_native_provider
typedef Impostor = provided_type("schemas/native", "Impostor")
[export]
def main() {
    var other = default<Impostor>
    apply_damage(other, 1) // Same fields, different nominal type: must fail.
}
