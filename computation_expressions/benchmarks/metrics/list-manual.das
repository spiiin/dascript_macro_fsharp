options gen2


def work(seed:int) : int64 {
    var inscope values:array<int>
    for(x in fixed_array(seed,seed+1,seed+2,seed+3)){
        for(y in fixed_array(1,2,3,4)){values |> push(x*y)}
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