options gen2
module task_http public
require ./task_jobque.das public
require dashv/dashv_boost
require strings

// dasHV exposes only a blocking HTTP client. Each request runs on a jobque worker
// and the waiting Task polls the result, so the game loop never blocks.
struct TaskHttpHeader {
    key:string
    value:string
}
struct TaskHttpRequest {
    method:string="GET"
    url:string
    body:string
    content_type:string
    headers:array<TaskHttpHeader>
    // Seconds, as in libhv. Cancelling the Task stops waiting but cannot abort
    // a request already in flight: these limits bound the worker instead.
    timeout_s:int=30
    connect_timeout_s:int=10
    follow_redirects:bool=true
}
struct TaskHttpResponse {
    status:int
    body:string
    headers:array<TaskHttpHeader>
}

def private ce_http_method(name:string) : http_method {
    let upper=to_upper(name)
    if(upper=="GET" || empty(upper)) {return http_method.GET}
    if(upper=="POST") {return http_method.POST}
    if(upper=="PUT") {return http_method.PUT}
    if(upper=="DELETE") {return http_method.DELETE}
    if(upper=="PATCH") {return http_method.PATCH}
    if(upper=="HEAD") {return http_method.HEAD}
    if(upper=="OPTIONS") {return http_method.OPTIONS}
    panic("task http: unsupported method {name}")
    return http_method.GET
}
def private ce_http_validate(request:TaskHttpRequest) {
    if(empty(request.url)) {panic("task http: url is empty")}
    if(request.timeout_s<=0 || request.timeout_s>65535) {panic("task http: timeout_s must be in 1..65535")}
    if(request.connect_timeout_s<=0 || request.connect_timeout_s>65535) {panic("task http: connect_timeout_s must be in 1..65535")}
    ce_http_method(request.method)
}

// Worker function: runs in a cloned context on a jobque thread.
// Transport failures panic; task_jobque converts that into Result.err.
def ce_http_work(request:TaskHttpRequest) : TaskHttpResponse {
    var response:TaskHttpResponse
    var failure=""
    with_http_request() $(var req) {
        req.method=ce_http_method(request.method)
        req.url:=request.url
        req |> set_timeout(request.timeout_s)
        req |> set_connect_timeout(request.connect_timeout_s)
        req |> allow_redirect(request.follow_redirects)
        for(header in request.headers) {req |> set_header(header.key,header.value)}
        if(!empty(request.content_type)) {req |> set_content_type(request.content_type)}
        if(!empty(request.body)) {req.body:=request.body}
        request(req) $(resp) {
            if(resp==null) {failure="task http: no response from {request.url}";return}
            response.status=int(resp.status_code)
            if(response.status<=0) {failure="task http: transport error for {request.url}";return}
            response.body=string(resp.body)
            each_header(resp) $(key,value) {
                response.headers |> push(TaskHttpHeader(key=clone_string(key),value=clone_string(value)))
            }
        }
    }
    if(!empty(failure)) {panic(failure)}
    return <- response
}

// Task<Result<TaskHttpResponse,string>>. HTTP error statuses (404, 500, ...) are
// successful responses; only transport failures (DNS, connect, timeout) are err.
def task_http(queue:tuple<tag:TaskJobQueueTag;owner:iterator<auto(S)?>>;request:TaskHttpRequest) {
    ce_http_validate(request)
    return <- task_jobque(queue,request,@@ce_http_work)
}
def task_http_get(queue:tuple<tag:TaskJobQueueTag;owner:iterator<auto(S)?>>;url:string) {
    var inscope request=TaskHttpRequest(url=url)
    return <- task_http(queue,request)
}
def task_http_post(queue:tuple<tag:TaskJobQueueTag;owner:iterator<auto(S)?>>;url:string;body:string;content_type:string="application/json") {
    var inscope request=TaskHttpRequest(method="POST",url=url,body=body,content_type=content_type)
    return <- task_http(queue,request)
}
// Case-insensitive header lookup; "" when missing.
def task_http_header(response:TaskHttpResponse;key:string) : string {
    let wanted=to_lower(key)
    for(header in response.headers) {if(to_lower(header.key)==wanted) {return header.value}}
    return ""
}
def task_http_ok(response:TaskHttpResponse) : bool {return response.status>=200 && response.status<300}
