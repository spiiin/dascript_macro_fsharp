options gen2
require ../../lib/computation.das
def checked(n:int) {
    if(n%7==0){return variant<ok:int;error:string>(error="invalid")}
    return variant<ok:int;error:string>(ok=n+1)
}
def work(seed:int) : int64 {
    let result=computation(ResultBuilder()) {
        let a=checked(seed) |> bind
        let b=checked(a*2) |> bind
        let c=checked(b+3) |> bind
        return c*2
    }
    return result is error ? -1l : int64(result as ok)
}
[export]
def main() {
    var checksum=0l
    for(seed in range(64)){checksum+=work(seed)}
    print("CHECKSUM,{checksum}\n")
}