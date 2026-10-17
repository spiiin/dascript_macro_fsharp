// SDK 0.6.4: native [async] inscope is finalized at the first suspension.
// The second next reports "invalid label index". No library modules are used.
// This known-failure repro is deliberately outside run_computation.ps1.
options gen2
require daslib/async_boost
struct Buffer {values:array<int>}
[async]
def source() : int {
    var inscope buffer <- Buffer(values <- [1,2,3])
    await_next_frame()
    yield length(buffer.values)
}
[export]
def main() {
    var inscope sourceIterator <- source()
    var event:variant<res:int;wait:bool>
    verify(next(sourceIterator,event))
    verify(next(sourceIterator,event))
}
