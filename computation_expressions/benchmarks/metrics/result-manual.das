options gen2

def checked(n:int) {
    if(n%7==0){return variant<ok:int;error:string>(error="invalid")}
    return variant<ok:int;error:string>(ok=n+1)
}
def work(seed:int) : int64 {
    let a=checked(seed)
    if(a is error){return -1l}
    let b=checked((a as ok)*2)
    if(b is error){return -1l}
    let c=checked((b as ok)+3)
    return c is error ? -1l : int64(c as ok)*2l
}
[export]
def main() {
    var checksum=0l
    for(seed in range(64)){checksum+=work(seed)}
    print("CHECKSUM,{checksum}\n")
}