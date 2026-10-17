options gen2
module coroutine_builder public
require ./builder_protocol.das public
require ./sequence_runtime.das public
require daslib/rtti

struct CoroutineBuilder {_ce_marker:uint8}
struct CoroutineWait {frames:int}
struct CoroutineFrame {_ce_marker:uint8}

def next_frame() {return CoroutineWait(frames=1)}
def wait_frames(frames:int) {
    if (frames<0) {panic("wait_frames: frame count must be non-negative")}
    return CoroutineWait(frames=frames)
}
def ce_protocol(builder:CoroutineBuilder) {return ce_sequence_protocol(type<CoroutineWait>)}

// Expand each suspension into exactly N frame boundaries. A yield is never
// inside try/recover; the outer protected iterator closes this owner on panic.
def ce_sequence_run(builder:CoroutineBuilder; var source:iterator<CoroutineWait>) : iterator<CoroutineFrame> {
    var frames <- generator<CoroutineFrame> capture(<-source) {
        var request=CoroutineWait()
        while (ce_sequence_next_value(source,request)) {
            if (request.frames<0) {panic("wait_frames: frame count must be non-negative")}
            for (i in range(request.frames)) {yield CoroutineFrame()}
        }
        return false
    } finally {ce_sequence_finalize($ {sequence_close(source)})}
    return <- ce_sequence_protect(frames)
}

// Await a child through `child |> yield_from`, forwarding one boundary per tick.
// The adapter owns the child, including when the parent is cancelled.
def ce_source(builder:CoroutineBuilder; var child:iterator<CoroutineFrame>) : iterator<CoroutineWait> {
    var requests <- generator<CoroutineWait> capture(<-child) {
        var frame=CoroutineFrame()
        while (ce_sequence_next_value(child,frame)) {yield next_frame()}
        return false
    } finally {ce_sequence_finalize($ {sequence_close(child)})}
    return <- ce_sequence_protect(requests)
}

// True: suspended at a frame boundary. False: completed and closed.
def coroutine_resume(var task:iterator<CoroutineFrame>) : bool {
    var frame=CoroutineFrame()
    var more=false
    try {more=ce_sequence_next_value(task,frame)} recover {
        let message="{this_context().last_exception}"
        sequence_close(task)
        panic(message)
    }
    if (!more) {sequence_close(task)}
    return more
}
def coroutine_cancel(var task:iterator<CoroutineFrame>) {sequence_close(task)}


