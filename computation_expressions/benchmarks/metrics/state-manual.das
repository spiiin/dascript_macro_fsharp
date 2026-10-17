options gen2


def work(seed:int) : int64 {
    var state=seed
    for(i in range(16)){state+=i}
    let result=(value=state*2,state=state)
    return int64(result.value)+int64(result.state)
}
[export]
def main() {
    var checksum=0l
    for(seed in range(64)){checksum+=work(seed)}
    print("CHECKSUM,{checksum}\n")
}