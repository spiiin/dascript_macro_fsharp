options gen2
require ../lib/computation.das
require ../lib/deferred_computation.das
var events=""
struct Observed {}
def builder() { events+="B"; return Observed() }
def environment() { events+="D"; return [7] }
def ce_protocol(b:Observed) { events+="P"; return CeValueProtocol() }
def ce_return(b:Observed; value:int) { events+="T"; return result_ok(value) }
def ce_run(b:Observed; result:variant<ok:int;error:string>) { events+="R"; return result as ok }
[export]
def main() {
    let baseline=heap_bytes_allocated()
    {
        var inscope task <- deferred(builder(),environment()) $(snapshot) {
            events+="E"
            return snapshot[0]
        }
        assert(events=="BD")
        let first=run_deferred(task)
        assert(first==7 && events=="BDETR")
        let second=run_deferred(task)
        assert(second==7 && events=="BDETRETR")
    }
    let after=heap_bytes_allocated()
    assert(after==baseline)
    print("deferred ordering checks OK\n")
}
