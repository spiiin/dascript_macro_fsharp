options gen2
module protocol_test_builders public
require ../lib/builder_protocol.das public
require ../lib/sequence_runtime.das public
require daslib/rtti

var protocolCalls = 0
var sequenceRuns = 0
var sequenceConstructors = 0
// A different nominal shape from the built-in tuple builder.
struct CustomSequenceBuilder { token : int }
def custom_sequence() {
    sequenceConstructors++
    return CustomSequenceBuilder(token=42)
}
def ce_protocol(builder : CustomSequenceBuilder) {
    protocolCalls++
    return ce_sequence_protocol(type<string>)
}
def ce_sequence_run(builder : CustomSequenceBuilder; var source : iterator<string>) : iterator<string> {
    assert(builder.token == 42)
    sequenceRuns++
    return <- ce_sequence_protect(source)
}

