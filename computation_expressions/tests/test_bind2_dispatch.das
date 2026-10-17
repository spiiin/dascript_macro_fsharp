options gen2
require ../lib/computation_macro.das
struct Probe {}
struct Legacy {}
var merges=0
var binds=0
var returns=0
var ones=0
var twos=0
var grouped=0
var order=""
def source(n:int) { order+="{n}"; return (value=n) }
def ce_protocol(builder:Probe) { return CeValueProtocol() }
def ce_protocol(builder:Legacy) { return CeValueProtocol() }
def ce_unwrap(builder:Probe; value:tuple<value:auto(T)>) : T { return value.value }
def ce_unwrap(builder:Legacy; value:tuple<value:auto(T)>) : T { return value.value }
def ce_return(builder:Probe; value:auto(T)) { returns++; return (value=value) }
def ce_return(builder:Legacy; value:auto(T)) { returns++; return (value=value) }
def ce_bind(builder:Probe; value:tuple<value:auto(T)>; next:block<(x:T):auto(R)>) : R { binds++; return invoke(next,value.value) }
def ce_bind(builder:Legacy; value:tuple<value:auto(T)>; next:block<(x:T):auto(R)>) : R { binds++; return invoke(next,value.value) }
def ce_merge_sources(builder:Probe; left:tuple<value:auto(A)>; right:tuple<value:auto(B)>) {
    merges++; return (value=ce_source_pair(left.value,right.value))
}
def ce_merge_sources(builder:Legacy; left:tuple<value:auto(A)>; right:tuple<value:auto(B)>) {
    merges++; return (value=ce_source_pair(left.value,right.value))
}
def ce_bind_return(builder:Probe; value:tuple<value:auto(T)>; mapper:block<(x:T):auto(U)>) {
    ones++; return (value=invoke(mapper,value.value))
}
def ce_bind2_return(builder:Probe; left:tuple<value:auto(A)>; right:tuple<value:auto(B)>;
                    mapper:block<(p:tuple<first:A -const -&;second:B -const -&>):auto(U)>) {
    twos++; return (value=invoke(mapper,ce_source_pair(left.value,right.value)))
}
def ce_bind2(builder:Probe; left:tuple<value:auto(A)>; right:tuple<value:auto(B)>;
             next:block<(p:tuple<first:A -const -&;second:B -const -&>):auto(R)>) : R {
    grouped++; return invoke(next,ce_source_pair(left.value,right.value))
}
struct OnlyTwo {}
def ce_protocol(builder:OnlyTwo) { return CeValueProtocol() }
def ce_unwrap(builder:OnlyTwo; value:tuple<value:auto(T)>) : T { return value.value }
def ce_return(builder:OnlyTwo; value:auto(T)) { returns++; return (value=value) }
def ce_bind(builder:OnlyTwo; value:tuple<value:auto(T)>; next:block<(x:T):auto(R)>) : R { binds++; return invoke(next,value.value) }
def ce_merge_sources(builder:OnlyTwo; left:tuple<value:auto(A)>; right:tuple<value:auto(B)>) {
    merges++; return (value=ce_source_pair(left.value,right.value))
}
def ce_bind2(builder:OnlyTwo; left:tuple<value:auto(A)>; right:tuple<value:auto(B)>;
             next:block<(p:tuple<first:A -const -&;second:B -const -&>):auto(R)>) : R {
    grouped++; return invoke(next,ce_source_pair(left.value,right.value))
}
[export]
def main() {
    let a=computation(Probe()) {
        let p=source(1) |> and_bind(source(2)) |> bind
        let n=p.first+p.second
        let x=source(n) |> bind
        return x*2
    }
    assert(a.value==6 && order=="123" && grouped==1 && merges==0 && binds==0 && ones==1)
    let b=computation(Probe()) { let p=source(4) |> and_bind(source(5)) |> bind; return p.first+p.second }
    assert(b.value==9 && grouped==1 && twos==1 && merges==0)
    let c=computation(Probe()) { source(6) |> and_bind(source(7)) |> bind; let n=8; return n }
    assert(c.value==8 && grouped==2 && returns==1)
    let d=computation(Legacy()) { let p=source(8) |> and_bind(source(9)) |> bind; let n=p.first+p.second; return n }
    assert(d.value==17 && merges==1 && binds==1 && returns==2)
    let e=computation(Probe()) { let p=source(1) |> and_bind(source(2)) |> and_bind(source(3)) |> bind; let n=p.first.first+p.first.second+p.second; return n }
    assert(e.value==6 && grouped==3 && merges==2 && order=="123456789123")
    let only=computation(OnlyTwo()) { let p=source(4) |> and_bind(source(5)) |> bind; return p.first+p.second }
    assert(only.value==9 && grouped==4 && merges==2 && twos==1 && ones==1 && binds==1)
    print("bind2 dispatch checks OK\n")
}
