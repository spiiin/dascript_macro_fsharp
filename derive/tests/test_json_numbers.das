options gen2
require ../lib/derive.das
require daslib/rtti
require strings
[derive(json=true)]
struct Numeric {
    exact:int64
    small:int8
    positive:uint16
    unsigned:uint64
    real:double
    flag:bool
}
def expect_parse_error(text:string) {
    var inscope result <- derive_from_json(text,type<Numeric>,"root")
    verify(!result.ok && length(result.errors)==1 && result.errors[0].code=="json_parse")
}
def check() {
    var inscope result <- derive_from_json("\{\"exact\":9007199254740993,\"small\":-128,\"positive\":65535,\"unsigned\":9223372036854775807,\"real\":1.25,\"flag\":true\}",type<Numeric>)
    verify(result.ok && result.value.exact==9007199254740993l && result.value.unsigned==9223372036854775807ul && result.value.small==int8(-128))
    var inscope roundtrip <- derive_from_json(derive_to_json(result.value),type<Numeric>)
    verify(roundtrip.ok && derive_equal(result.value,roundtrip.value))
    var inscope bad <- derive_from_json("\{\"exact\":1.5,\"small\":128,\"positive\":-1,\"unsigned\":-1,\"real\":\"bad\",\"flag\":0\}",type<Numeric>)
    verify(!bad.ok && length(bad.errors)==6 && bad.errors[1].code=="json_range" && bad.errors[2].code=="json_range")
    var inscope tooLarge <- derive_from_json("9223372036854775808",type<uint64>)
    verify(!tooLarge.ok && tooLarge.errors[0].code=="json_range") // SDK DOM cannot retain integers above signed int64.
    var caught=false
    try {let ignored=derive_to_json(18446744073709551615ul)} recover {caught=true}
    verify(caught)
    caught=false
    let nan=unsafe(reinterpret<float>(0x7fc00000u))
    try {let ignored=derive_to_json(nan)} recover {caught=true}
    verify(caught)
    expect_parse_error("\{\"exact\":1,\"exact\":2\}")
    expect_parse_error("\{\} trailing")
    expect_parse_error("\{\"exact\":[1,2,\{\"a\":\"unterminated")
    expect_parse_error("\{\"exact\":01\}")
    var inscope nullValue <- derive_from_json("null",type<Numeric>)
    verify(!nullValue.ok && nullValue.errors[0].code=="json_type")
    var inscope limited <- derive_from_json("\{\"x\":[1,2]\}",type<Numeric>,"",JsonReadLimits(max_bytes=4))
    verify(!limited.ok && limited.errors[0].code=="json_parse")
    var inscope number <- derive_from_json("42",type<int>)
    verify(number.ok && number.value==42)
    var inscope scalar <- derive_from_json("false",type<bool>)
    verify(scalar.ok && !scalar.value)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive JSON numeric and parser checks OK\n")
}
