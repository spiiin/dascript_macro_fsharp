options gen2
require ../lib/derive.das
require daslib/rtti
[derive(validate=true)]
struct Numbers {
    @validate_min=9007199254740993l
    @validate_max=9007199254740995l
    exact:int64
    @validate_min=18446744073709551614ul
    @validate_max=18446744073709551615ul
    large:uint64
    @validate_min=-2
    @validate_max=2
    signed:int
    @validate_min=-1
    @validate_max=3
    unsigned:uint
    @validate_min=-1.5
    @validate_max=2.5
    real:double
}
[derive(validate=true)]
struct Floating {
    @validate_min=-1.0
    @validate_max=1.0
    value:float
}
[derive(validate=true)]
struct TextRules {
    @validate_non_empty
    @validate_min_length=2
    @validate_max_length=4
    text:string
    @validate_min_length=2
    @validate_max_length=2
    fixedValues:int[2]
    @validate_non_empty=false
    disabled:string
}
def check() {
    var v=Numbers(exact=9007199254740993l,large=18446744073709551615ul,signed=-2,unsigned=uint(0),real=-1.5lf)
    var inscope good <- derive_validate(v)
    verify(length(good)==0)
    v.exact=9007199254740992l;v.large=18446744073709551613ul;v.signed=3;v.unsigned=uint(4);v.real=3.0lf
    var inscope bad <- derive_validate(v)
    verify(length(bad)==5 && bad[0].code=="min" && bad[1].code=="min" && bad[2].code=="max")
    v.exact=9007199254740996l
    var inscope upper <- derive_validate(v)
    verify(upper[0].code=="max")
    let nan=unsafe(reinterpret<float>(0x7fc00000u))
    var inscope nanErrors <- derive_validate(Floating(value=nan))
    verify(length(nanErrors)==2)
    var inscope infinityErrors <- derive_validate(Floating(value=unsafe(reinterpret<float>(0x7f800000u))))
    verify(length(infinityErrors)==1 && infinityErrors[0].code=="max")
    var text:TextRules
    var inscope empty <- derive_validate(text)
    verify(length(empty)==2)
    text.text="ёж" // Four UTF-8 bytes, not two characters.
    var inscope utf8 <- derive_validate(text)
    verify(length(utf8)==0)
    text.text="abcde"
    var inscope longText <- derive_validate(text)
    verify(length(longText)==1 && longText[0].code=="max_length")
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive validation numeric checks OK\n")
}
