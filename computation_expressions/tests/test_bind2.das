options gen2
require ../lib/computation.das
require ../lib/validation_builder.das
var order=""
var calls=0
def observed(n:int; value:auto(T)) : T { order+="{n}"; return value }
def later() { calls++; return 7 }
[export]
def main() {
    {
        order=""; calls=0
        let r0=computation(ResultBuilder()) {
            let p=observed(1,result_ok(2)) |> and_bind(observed(2,result_ok(3))) |> bind
            let n=later()
            return p.first+p.second+n
        }
        assert(order=="12" && calls==1 && r0 is ok)
        order=""; calls=0
        let r1=computation(ResultBuilder()) {
            let p=observed(1,result_error("failure",type<int>)) |> and_bind(observed(2,result_ok(3))) |> bind
            let n=later()
            return p.first+p.second+n
        }
        assert(order=="12" && calls==0 && r1 is err)
        order=""; calls=0
        let r2=computation(ResultBuilder()) {
            let p=observed(1,result_ok(2)) |> and_bind(observed(2,result_error("failure",type<int>))) |> bind
            let n=later()
            return p.first+p.second+n
        }
        assert(order=="12" && calls==0 && r2 is err)
        order=""; calls=0
        let r3=computation(ResultBuilder()) {
            let p=observed(1,result_error("failure",type<int>)) |> and_bind(observed(2,result_error("failure",type<int>))) |> bind
            let n=later()
            return p.first+p.second+n
        }
        assert(order=="12" && calls==0 && r3 is err)
        let fast=computation(ResultBuilder()) {
            let p=result_ok((name="Mage",level=2)) |> and_bind(result_ok(3)) |> bind
            let n=p.second
            return (hero=p.first,number=n)
        }
        let slow=computation(ResultBuilder()) {
            let p=ce_merge_sources(ResultBuilder(),result_ok((name="Mage",level=2)),result_ok(3)) |> bind
            let n=p.second
            return (hero=p.first,number=n)
        }
        assert((typeinfo typename(fast))==(typeinfo typename(slow)))
        assert((fast as ok).hero.name==(slow as ok).hero.name && (fast as ok).number==3)
    }
    {
        order=""; calls=0
        let r0=computation(OptionBuilder()) {
            let p=observed(1,some(2)) |> and_bind(observed(2,some(3))) |> bind
            let n=later()
            return p.first+p.second+n
        }
        assert(order=="12" && calls==1 && r0 is some)
        order=""; calls=0
        let r1=computation(OptionBuilder()) {
            let p=observed(1,none(type<int>)) |> and_bind(observed(2,some(3))) |> bind
            let n=later()
            return p.first+p.second+n
        }
        assert(order=="12" && calls==0 && r1 is none)
        order=""; calls=0
        let r2=computation(OptionBuilder()) {
            let p=observed(1,some(2)) |> and_bind(observed(2,none(type<int>))) |> bind
            let n=later()
            return p.first+p.second+n
        }
        assert(order=="12" && calls==0 && r2 is none)
        order=""; calls=0
        let r3=computation(OptionBuilder()) {
            let p=observed(1,none(type<int>)) |> and_bind(observed(2,none(type<int>))) |> bind
            let n=later()
            return p.first+p.second+n
        }
        assert(order=="12" && calls==0 && r3 is none)
        let fast=computation(OptionBuilder()) {
            let p=some((name="Mage",level=2)) |> and_bind(some(3)) |> bind
            let n=p.second
            return (hero=p.first,number=n)
        }
        let slow=computation(OptionBuilder()) {
            let p=ce_merge_sources(OptionBuilder(),some((name="Mage",level=2)),some(3)) |> bind
            let n=p.second
            return (hero=p.first,number=n)
        }
        assert((typeinfo typename(fast))==(typeinfo typename(slow)))
        assert((fast as some).hero.name==(slow as some).hero.name && (fast as some).number==3)
    }
    {
        order=""; calls=0
        let r0=computation(ValidationBuilder()) {
            let p=observed(1,validation_ok(2)) |> and_bind(observed(2,validation_ok(3))) |> bind
            let n=later()
            return p.first+p.second+n
        }
        assert(order=="12" && calls==1 && r0 is valid)
        order=""; calls=0
        let r1=computation(ValidationBuilder()) {
            let p=observed(1,validation_error("failure",type<int>)) |> and_bind(observed(2,validation_ok(3))) |> bind
            let n=later()
            return p.first+p.second+n
        }
        assert(order=="12" && calls==0 && r1 is invalid)
        order=""; calls=0
        let r2=computation(ValidationBuilder()) {
            let p=observed(1,validation_ok(2)) |> and_bind(observed(2,validation_error("failure",type<int>))) |> bind
            let n=later()
            return p.first+p.second+n
        }
        assert(order=="12" && calls==0 && r2 is invalid)
        order=""; calls=0
        let r3=computation(ValidationBuilder()) {
            let p=observed(1,validation_error("failure",type<int>)) |> and_bind(observed(2,validation_error("failure",type<int>))) |> bind
            let n=later()
            return p.first+p.second+n
        }
        assert(order=="12" && calls==0 && r3 is invalid)
        assert((r3 as invalid).count==2 && (r3 as invalid).messages=="failure\nfailure")
        let fast=computation(ValidationBuilder()) {
            let p=validation_ok((name="Mage",level=2)) |> and_bind(validation_ok(3)) |> bind
            let n=p.second
            return (hero=p.first,number=n)
        }
        let slow=computation(ValidationBuilder()) {
            let p=ce_merge_sources(ValidationBuilder(),validation_ok((name="Mage",level=2)),validation_ok(3)) |> bind
            let n=p.second
            return (hero=p.first,number=n)
        }
        assert((typeinfo typename(fast))==(typeinfo typename(slow)))
        assert((fast as valid).hero.name==(slow as valid).hero.name && (fast as valid).number==3)
    }
    calls=0
    let nested=computation(ResultBuilder()) {
        let p=result_ok(1) |> and_bind(result_ok(2)) |> bind
        let n=result_error("later failure",type<int>) |> bind
        let unused=later()
        return p.first+p.second+n
    }
    assert(nested is err && nested as err=="later failure" && calls==0)
    order=""
    var caught=false
    try {
        let r=computation(ResultBuilder()) {
            let p=observed(1,result_ok(1)) |> and_bind(explode()) |> bind
            let unused=later()
            return p.first+p.second
        }
    } recover { caught=true }
    assert(caught && order=="1" && calls==0)
    print("bind2 value checks OK\n")
}
def explode() : $Result<int;string> { panic("source failed"); return result_ok(0) }
