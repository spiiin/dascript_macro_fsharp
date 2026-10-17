options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
struct UnsafeLoot {items:array<int>;pointer:int?}
[export]
def main() {
    var inscope task <- deferred(SequenceBuilder(type<UnsafeLoot>)) {yield <- UnsafeLoot()}
}
