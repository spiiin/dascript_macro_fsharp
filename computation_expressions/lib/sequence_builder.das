options gen2
module sequence_builder public
require ./builder_protocol.das public
require ./sequence_runtime.das public
struct SequenceContext {}
struct MoveSequenceContext {}
def SequenceBuilder(t : type<auto(T)>) {
    static_if (typeinfo can_copy(type<T>)) {
        var element:T -const
        return (kind=SequenceContext(),element=element)
    } else {
        var marker:T -const -&?
        return (kind=MoveSequenceContext(),element=marker)
    }
}

def SequenceBuilder() { return SequenceBuilder(type<int>) }



def ce_protocol(builder : tuple<kind:SequenceContext;element:auto(T)>) {
    return ce_sequence_protocol(type<T>)
}
def ce_sequence_run(builder : tuple<kind:SequenceContext;element:auto(T)>; var source : iterator<T>) : iterator<T> {
    return <- ce_sequence_protect(source)
}

def ce_protocol(builder:tuple<kind:MoveSequenceContext;element:auto(T)?>) {
    return <- (strategy=CeSequenceProtocol(),element <- default<T>)
}
def ce_sequence_run(builder:tuple<kind:MoveSequenceContext;element:auto(T)?>; var source:iterator<T>) {
    return <- ce_sequence_own_elements(source)
}
