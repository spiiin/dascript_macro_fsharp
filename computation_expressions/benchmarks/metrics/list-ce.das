options gen2
require ../../lib/computation.das

def work(seed:int) : int64 {
    var inscope values <- computation(ListBuilder()) {
        let x=fixed_array(seed,seed+1,seed+2,seed+3) |> bind
        let y=fixed_array(1,2,3,4) |> bind
        return x*y
    }
    var total=0l
    for(i in range(length(values))){total+=int64(i+1)*int64(values[i])}
    return total
}
[export]
def main() {
    var checksum=0l
    for(seed in range(64)){checksum+=work(seed)}
    print("CHECKSUM,{checksum}\n")
}