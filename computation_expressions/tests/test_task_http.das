options gen2
require ../lib/computation.das
require ../lib/task_runtime.das
require ../lib/task_http.das
require ../lib/task_parallel.das
require daslib/rtti
require daslib/fio
require strings

var queue:typedecl(task_job_queue())

def wait(var runtime:auto;ticket:auto;var now:int&) {
    for(i in range(1000000)) {
        task_tick(runtime,now);now++
        let status=task_status(ticket)
        if(status!=TaskStatus.Waiting && status!=TaskStatus.Created) {return}
        sleep(1u)
    }
}

[export]
def main() {
    let port=get_env_variable("CE_HTTP_PORT")
    verify(!empty(port))
    let base="http://127.0.0.1:{port}"
    with_job_que() {
        queue <- task_job_queue()
        var inscope runtime <- task_runtime()
        var now=0
        {
            var inscope get <- task_spawn(runtime,task_http_get(queue,"{base}/hello"))
            wait(runtime,get,now)
            let r=task_value(get)
            verify(r is ok && (r as ok).status==200 && (r as ok).body=="hello")
            verify(task_http_ok(r as ok) && task_http_header(r as ok,"x-fixture")=="yes")
        }
        {
            var inscope post <- task_spawn(runtime,task_http_post(queue,"{base}/echo","\{\"hp\":85\}"))
            wait(runtime,post,now)
            let r=task_value(post)
            verify(r is ok && (r as ok).status==201 && (r as ok).body=="\{\"hp\":85\}")
            verify(task_http_header(r as ok,"Content-Type")=="application/json")
        }
        {
            var inscope request <- TaskHttpRequest(url="{base}/header")
            request.headers |> push(TaskHttpHeader(key="X-Token",value="secret"))
            var inscope custom <- task_spawn(runtime,task_http(queue,request))
            var inscope missing <- task_spawn(runtime,task_http_get(queue,"{base}/missing"))
            wait(runtime,custom,now);wait(runtime,missing,now)
            verify((task_value(custom) as ok).body=="secret")
            // HTTP error statuses are responses, not transport errors.
            verify(task_value(missing) is ok && (task_value(missing) as ok).status==404 && !task_http_ok(task_value(missing) as ok))
        }
        {
            // Connection refused (nothing listens on port 1) is a transport error.
            var inscope refused <- task_spawn(runtime,task_http(queue,TaskHttpRequest(url="http://127.0.0.1:1/",timeout_s=2,connect_timeout_s=1)))
            wait(runtime,refused,now)
            verify(task_value(refused) is err)
        }
        {
            // A Task timeout stops waiting; the in-flight request finishes on the worker.
            var inscope slow <- task_spawn(runtime,task_http_get(queue,"{base}/slow"),TaskTimeout(after_ms=50))
            wait(runtime,slow,now)
            verify(task_timed_out(runtime,slow))
        }
        {
            // Retry and limited when_all compose with HTTP tasks.
            var inscope urls <- ["{base}/hello","{base}/missing","{base}/hello"]
            var inscope all <- task_spawn(runtime,task_result_when_all_limited(urls,2,@(url:string) {return <- task_http_get(queue,url)}))
            wait(runtime,all,now)
            let r=task_value(all)
            verify(r is ok && length(r as ok)==3 && (r as ok)[1].status==404 && (r as ok)[2].body=="hello")
        }
        var failed=false
        try {var inscope bad <- task_http(queue,TaskHttpRequest(url=""))} recover {failed=true}
        verify(failed)
        for(i in range(100000)) {task_jobque_collect(queue);if(task_jobque_channels()==0) {break};sleep(1u)}
        delete runtime
        delete queue
    }
    verify(task_jobque_channels()==0)
    print("Task http checks OK\n")
}
