options gen2
require ../lib/computation.das

def borrowed(var values:array<int>) : array<int>& { unsafe { return values } }
struct Holder { values:array<int> }
[export]
def main() {
    let baseline=heap_bytes_allocated()
    {
        var inscope holder=Holder()
        holder.values |> push(3)
        var inscope values <- computation(ListBuilder()) {
            let p = holder.values |> and_bind(borrowed(holder.values)) |> and_bind([4]) |> bind
            return p.first.first+p.first.second+p.second
        }
        assert(length(holder.values)==1 && values[0]==10)
        var inscope nested <- computation(ListBuilder()) {
            let p = [1,2] |> and_bind([10] |> and_bind([100])) |> bind
            return p.first+p.second.first+p.second.second
        }
        assert(length(nested)==2 && nested[0]==111 && nested[1]==112)
    }
    let after=heap_bytes_allocated()
    assert(after==baseline)
    print("and_bind reference checks OK\n")
}
