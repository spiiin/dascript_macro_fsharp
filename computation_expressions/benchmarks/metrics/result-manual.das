options gen2
require daslib/result

def checked(n:int) {
    if(n%7==0){return variant type<$Result<int;string>>(err="invalid")}
    return variant type<$Result<int;string>>(ok=n+1)
}
def work(seed:int) : int64 {
    let a=checked(seed)
    if(a is err){return -1l}
    let b=checked((a as ok)*2)
    if(b is err){return -1l}
    let c=checked((b as ok)+3)
    return c is err ? -1l : int64(c as ok)*2l
}
[export]
def main() {
    var checksum=0l
    for(seed in range(64)){checksum+=work(seed)}
    print("CHECKSUM,{checksum}\n")
}
