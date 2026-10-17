options gen2
require ../lib/computation.das
var cleanups=0
struct Resource {}
def ce_dispose(var resource:Resource) { cleanups++ }
[export]
def main() {
    let baseline=heap_bytes_allocated()
    for (iteration in range(20)) {
        {
            var inscope values <- computation(ListBuilder()) {
                yield 1
                for (i in range(3)) { yield i }
                if (true) { yield 7 }
                yield 9
            }
            assert(length(values)==6 && values[0]==1 && values[5]==9)
        }
        {
            var inscope values <- computation(ListBuilder()) {
                let p=ce_merge_sources(ListBuilder(),fixed_array(1,2),fixed_array(10,20)) |> bind
                let n=p.first+p.second
                return n
            }
            assert(length(values)==4 && values[3]==22)
        }
        var caught=false
        try {
            var inscope ignored <- computation(ListBuilder()) {
                let resource=Resource() |> use_resource
                yield 1
                let x=[2,3] |> bind
                if (x==3) { panic("later failed") }
                return x
            }
        } recover { caught=true }
        assert(caught)
        let after=heap_bytes_allocated()
        assert(after==baseline)
    }
    assert(cleanups==20)
    print("collect temporary checks OK\n")
}
