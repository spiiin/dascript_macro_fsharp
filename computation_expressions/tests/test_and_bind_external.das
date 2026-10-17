options gen2
require ../lib/computation_macro.das
require ../lib/reader_builder.das

var merged = 0
def ce_merge_sources(builder : tuple<kind:ReaderContext;environment:auto(E)>;
                     left : tuple<value:auto(A)>; right : tuple<value:auto(B)>) {
    merged++
    return reader_value(ce_source_pair(left.value, right.value))
}
[export]
def main() {
    let result = computation(ReaderBuilder(0)) {
        let pair = reader_value(5) |> and_bind(reader_value("external")) |> bind
        return "{pair.second}:{pair.first}"
    }
    assert(result.value == "external:5" && merged == 1)
    print("and_bind external protocol OK\n")
}
