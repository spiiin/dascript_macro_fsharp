options gen2
require ./builder_model.das
[export]
def main() {
    var inscope draft <- derive_builder(type<BuildPlayer>)
    draft |> builder_name("Alice")
    draft |> builder_note(none(type<string>))
    var inscope result <- derive_build(draft)
    verify(result.ok && (result.value as some).health==100)
    print("{derive_debug(result.value as some)}\n")
    print("Derive builder demo OK\n")
}
