options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
struct PointerSequence {}
def ce_protocol(builder:PointerSequence) { return ce_sequence_protocol(type<int?>) }
def ce_sequence_run(builder:PointerSequence; var source:iterator<int?>) { return <- ce_sequence_protect(source) }
[export]
def main() {
    var inscope task <- deferred(PointerSequence(),7) $(snapshot) { yield unsafe(addr(snapshot)) }
}
