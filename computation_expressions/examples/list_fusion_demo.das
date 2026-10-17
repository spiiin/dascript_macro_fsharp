options gen2
require ../lib/computation.das
[export]
def main() {
    var inscope values <- computation(ListBuilder()) {
        let a=fixed_array(1,2,3,4) |> bind
        let b=fixed_array(10,20,30,40) |> bind
        return a*b
    }
    assert(length(values)==16 && values[0]==10 && values[15]==160)
    print("List fused demo OK\n")
}
