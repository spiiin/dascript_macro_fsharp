options gen2
module task_hv public
require ./task_builder.das public
require dashv/dashv_boost
require strings

struct HvWebSocketConfig {
    max_message_bytes:int=65536
    max_queued_messages:int=16
    max_queued_bytes:int=262144
}
var private hv_created=0
var private hv_released=0
var private hv_started=0
var private hv_stopped=0
var private hv_ops_created=0
var private hv_ops_released=0

// The native adapter queues callbacks; only process_event_que invokes das code.
class CeHvSocket : HvWebSocketClient {
    references:uint64=uint64(1)
    disposed:bool
    attempted:bool
    opened:bool
    was_opened:bool
    peer_closed:bool
    error:string
    messages:array<string>
    queued_bytes:int
    config:HvWebSocketConfig=HvWebSocketConfig()
    active:int64
    serial:int64

    def override onOpen() {opened=true;was_opened=true}
    def override onClose() {opened=false;peer_closed=true}
    def accept_text(msg:string#;count:int) {
        if(disposed || !empty(error)) {return}
        if(count<0 || count>config.max_message_bytes) {error="WebSocket: message exceeds max_message_bytes";return}
        if(length(msg)!=count) {error="WebSocket: text containing NUL is unsupported";return}
        if(length(messages)>=config.max_queued_messages || count>config.max_queued_bytes-queued_bytes) {
            error="WebSocket: receive queue limit exceeded";return
        }
        messages |> push(string(msg))
        queued_bytes+=count
    }
    def override onMessage(msg:string#) {self.accept_text(msg,length(msg))}
    def override onMessageFrame(msg:string#;count:int;opcode:ws_opcode) {
        if(opcode==ws_opcode.WS_OPCODE_TEXT) {self.accept_text(msg,count)}
        else {if(empty(error)) {error="WebSocket: binary messages are unsupported by ws_receive_text"}}
    }
}

// A move-only public owner. Operation leases retain the das object, not ownership
// of the connection: disposing this owner closes transport immediately.
struct HvWebSocket {lease:iterator<CeHvSocket?>}

def hv_websocket_stats() {
    return (created=hv_created,released=hv_released,active=hv_created-hv_released,
        clients_started=hv_started,clients_stopped=hv_stopped,active_clients=hv_started-hv_stopped,
        operations_created=hv_ops_created,operations_released=hv_ops_released,
        active_operations=hv_ops_created-hv_ops_released)
}

def private ce_hv_shutdown(var state:CeHvSocket?) {
    unsafe {
        if(state.disposed) {return}
        state.disposed=true
        state.opened=false
        if(is_alive(state.client)) {state.cleanup();hv_stopped++}
        delete state.messages
        state.queued_bytes=0
    }
}

def private ce_hv_lease(var state:CeHvSocket?) {
    return <- generator<CeHvSocket?> capture(copy(state)) {
        while(true) {yield state}
        return false
    } finally {ce_sequence_finalize($ {
        unsafe {
            state.references--
            if(state.references==uint64(0)) {
                ce_hv_shutdown(state)
                delete state
                hv_released++
            }
        }
    })}
}

def private ce_hv_state(socket:HvWebSocket) : CeHvSocket? {
    unsafe {
        var lease=reinterpret<iterator<CeHvSocket?>?>(addr(socket.lease))
        var state:CeHvSocket?
        if(!next(*lease,state)) {panic("WebSocket: owner has been moved or deleted")}
        return state
    }
}

def hv_websocket(config:HvWebSocketConfig=HvWebSocketConfig()) : HvWebSocket {
    if(config.max_message_bytes<1 || config.max_queued_messages<1 || config.max_queued_bytes<1) {
        panic("hv_websocket: limits must be positive")
    }
    var state=new CeHvSocket(config=config)
    hv_created++
    return <- HvWebSocket(lease <- ce_hv_lease(state))
}

def ce_dispose(var socket:HvWebSocket) {
    ce_sequence_finalize($ {
        var state:CeHvSocket?
        if(next(socket.lease,state)) {ce_hv_shutdown(state)}
        sequence_close(socket.lease)
    })
}
def finalize(var socket:HvWebSocket) {ce_dispose(socket)}

struct CeHvOperation {
    lease:iterator<CeHvSocket?>
    state:CeHvSocket?
    argument:string
    kind:int // connect=0, send=1, receive=2
    claimed:bool
    done:bool
    serial:int64
}

def private ce_hv_operation(socket:HvWebSocket;kind:int;argument:string="") {
    var state=ce_hv_state(socket)
    unsafe {
        if(state.references==uint64(-1)) {panic("WebSocket: reference count exhausted")}
        state.references++
        hv_ops_created++
        return new CeHvOperation(lease <- ce_hv_lease(state),state=state,kind=kind,argument=argument)
    }
}

def private ce_hv_begin(var op:CeHvOperation?) : string {
    unsafe {
        var state=op.state
        if(state.disposed) {return "WebSocket: owner was disposed"}
        if(op.claimed) {return ""}
        if(state.active!=0l) {return "WebSocket: another operation is active"}
        if(state.serial==9223372036854775807l) {return "WebSocket: operation serial exhausted"}
        state.serial++;state.active=state.serial
        op.serial=state.serial;op.claimed=true
        return ""
    }
}

def private ce_hv_finish(var op:CeHvOperation?) {
    unsafe {
        var state=op.state
        // Closing an unfinished active operation aborts the whole connection.
        // An unpolled/busy-rejected operation never cancels another operation.
        if(op.claimed && state.active==op.serial) {
            state.active=0l
            if(!op.done) {ce_hv_shutdown(state)}
        }
        // The lease owns the reference; this pointer is only an alias.
        op.state=null
        sequence_close(op.lease)
        delete op
        hv_ops_released++
    }
}

def private ce_hv_unit_error(var op:CeHvOperation?;message:string) {
    unsafe {op.done=true}
    return task_ready(result_error(message,type<CeUnit>))
}

def private ce_hv_poll_unit(var op:CeHvOperation?) {
    let failure=ce_hv_begin(op)
    if(!empty(failure)) {return ce_hv_unit_error(op,failure)}
    unsafe {
        var state=op.state
        if(op.kind==0) {
            if(!state.attempted) {
                if(!starts_with(op.argument,"ws://") && !starts_with(op.argument,"wss://")) {
                    return ce_hv_unit_error(op,"WebSocket: URL must start with ws:// or wss://")
                }
                state.attempted=true
                let code=state.init(op.argument)
                if(is_alive(state.client)) {hv_started++}
                if(code!=0) {ce_hv_shutdown(state);return ce_hv_unit_error(op,"WebSocket: open failed ({code})")}
            } elif(!op.done && state.was_opened) {
                return ce_hv_unit_error(op,"WebSocket: connection has already been opened")
            }
            state.process_event_que()
            if(!empty(state.error)) {let message=state.error;ce_hv_shutdown(state);return ce_hv_unit_error(op,message)}
            if(state.was_opened) {op.done=true;return task_ready(result_ok(CeUnit()))}
            if(state.peer_closed) {ce_hv_shutdown(state);return ce_hv_unit_error(op,"WebSocket: closed before handshake completed")}
            return task_pending(type<variant<ok:CeUnit;error:string>>)
        }
        state.process_event_que()
        if(!empty(state.error)) {let message=state.error;ce_hv_shutdown(state);return ce_hv_unit_error(op,message)}
        if(!state.opened) {return ce_hv_unit_error(op,"WebSocket: connection is not open")}
        let code=state.send_result(op.argument)
        if(code<0) {ce_hv_shutdown(state);return ce_hv_unit_error(op,"WebSocket: send failed ({code})")}
        op.done=true
        return task_ready(result_ok(CeUnit()))
    }
}

def ws_connect(socket:HvWebSocket;url:string) {
    var op=ce_hv_operation(socket,0,url)
    return <- task_from_poll(@(){return ce_hv_poll_unit(op)},@(){ce_hv_finish(op)})
}

def ws_send_text(socket:HvWebSocket;text:string) {
    var op=ce_hv_operation(socket,1,text)
    return <- task_from_poll(@(){return ce_hv_poll_unit(op)},@(){ce_hv_finish(op)})
}

def private ce_hv_text_error(var op:CeHvOperation?;message:string) {
    unsafe {op.done=true}
    return task_ready(result_error(message,type<string>))
}

def private ce_hv_poll_text(var op:CeHvOperation?) {
    let failure=ce_hv_begin(op)
    if(!empty(failure)) {return ce_hv_text_error(op,failure)}
    unsafe {
        var state=op.state
        if(!state.attempted) {return ce_hv_text_error(op,"WebSocket: connection is not open")}
        state.process_event_que()
        if(!empty(state.error)) {let message=state.error;ce_hv_shutdown(state);return ce_hv_text_error(op,message)}
        if(!empty(state.messages)) {
            let message=state.messages[0]
            state.queued_bytes-=length(message)
            state.messages |> erase(0)
            op.done=true
            return task_ready(result_ok(message))
        }
        if(state.peer_closed) {return ce_hv_text_error(op,"WebSocket: closed before a text message arrived")}
        return task_pending(type<variant<ok:string;error:string>>)
    }
}

def ws_receive_text(socket:HvWebSocket) {
    var op=ce_hv_operation(socket,2)
    return <- task_from_poll(@(){return ce_hv_poll_text(op)},@(){ce_hv_finish(op)})
}
