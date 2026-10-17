options gen2
module task_tcp public
require ./task_builder.das public
require daslib/network
require daslib/strings_boost

var private tcp_created=0
var private tcp_released=0
def task_tcp_stats() {return (created=tcp_created,released=tcp_released,active=tcp_created-tcp_released)}

// One bounded line per connection. connect() has the SDK's bounded synchronous
// connect phase; tick()/receive are nonblocking. All calls stay on one thread.
class CeTaskTcpLine : Client {
    bytes:array<uint8>
    error:string
    complete:bool
    limit:int
    def CeTaskTcpLine(max_bytes:int) {
        super()
        limit=max_bytes
        make_client_adapter()
        tcp_created++
    }
    def finalize() {
        close()
        delete bytes
        delete super.self
        tcp_released++
    }
    def override onConnect() {}
    def override onDisconnect() {if(!complete && empty(error)) {error="connection closed before a complete line"}}
    def override onLog(message:string) {}
    def override onError(message:string;code:int) {if(empty(error)) {error="{message} ({code})"}}
    def override onData(buffer:uint8?;size:int) {
        if(complete || !empty(error)) {return}
        for(i in range(size)) {
            let byte=unsafe(buffer[i])
            if(byte==uint8(10)) {complete=true;break}
            if(length(bytes)>=limit) {error="line exceeds max_bytes";break}
            bytes |> push(byte)
        }
    }
}

def task_tcp_request_line(host:string;port:int;request:string;max_bytes:int=65536;connect_timeout_ms:int=1000) {
    if(port<1 || port>65535 || max_bytes<1 || connect_timeout_ms<1) {panic("task_tcp_request_line: invalid limits")}
    if(length(request)>4096) {panic("task_tcp_request_line: request is limited to 4096 bytes")}
    var reader=new CeTaskTcpLine(max_bytes)
    if(reader.connect(host,port,connect_timeout_ms)) {
        peek_data(request) $(data) {
            if(!empty(data)) {unsafe {if(!reader.send(reinterpret<uint8?>(addr(data[0])),length(data))) {reader.error="failed to send request"}}}
        }
    } elif(empty(reader.error)) {reader.error="connection failed"}
    return <- task_from_poll(@() {
        reader.tick()
        if(!empty(reader.error)) {return task_ready(result_error(reader.error,type<string>))}
        if(reader.complete) {return task_ready(result_ok(string(reader.bytes)))}
        return task_pending(type<variant<ok:string;error:string>>)
    },@() {unsafe {delete reader}})
}
