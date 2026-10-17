options gen2
var cleaned=0
def protect(body:block<():auto(R)>; cleanup:block<():void>) : R {
    var result:R
    try {result=invoke(body)} recover {invoke(cleanup); panic("expected")}
    invoke(cleanup)
    return result
}
def catch_value(body:block<():auto(R)>; handler:block<():R>) : R {
    var result:R
    try {result=invoke(body)} recover {return invoke(handler)}
    return result
}
[export]
def main() {
    var state=(hp=0)
    let result=catch_value($ {
        return protect($ {
            state.hp=12
            panic("expected")
            return (value=0,state=state.hp)
        },$ {cleaned++})
    },$ {return (value=state.hp,state=state.hp)})
    assert(result.value==12 && result.state==12 && cleaned==1)
    print("tuple panic OK\n")
}
