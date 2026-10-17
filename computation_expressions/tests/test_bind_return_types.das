options gen2
require ../lib/computation.das
require ../lib/validation_builder.das
require ../lib/reader_builder.das
[export]
def main() {
    let fast=computation(ResultBuilder()) { let x=result_ok(1) |> bind; return (value=x+1) }
    let slow=computation(ResultBuilder()) { let x=result_ok(1) |> bind; let unused=0; return (value=x+1) }
    assert((typeinfo typename(fast)) == (typeinfo typename(slow)))
    let optionFast=computation(OptionBuilder()) { let x=some(1) |> bind; return (value="{x}") }
    let optionSlow=computation(OptionBuilder()) { let x=some(1) |> bind; let unused=0; return (value="{x}") }
    assert((typeinfo typename(optionFast)) == (typeinfo typename(optionSlow)))
    let validationFast=computation(ValidationBuilder()) { let x=validation_ok(1) |> bind; return (value=x+1) }
    let validationSlow=computation(ValidationBuilder()) { let x=validation_ok(1) |> bind; let unused=0; return (value=x+1) }
    assert((typeinfo typename(validationFast)) == (typeinfo typename(validationSlow)))
    let writerFast=computation(WriterBuilder()) { let x=writer_value(1,"log") |> bind; return (value=x+1) }
    let writerSlow=computation(WriterBuilder()) { let x=writer_value(1,"log") |> bind; let unused=0; return (value=x+1) }
    assert((typeinfo typename(writerFast)) == (typeinfo typename(writerSlow)))
    assert(writerFast.value.value==writerSlow.value.value && writerFast.log==writerSlow.log)
    let readerFast=computation(ReaderBuilder(1)) { let x=reader_ask() |> bind; return (value=x+1) }
    let readerSlow=computation(ReaderBuilder(1)) { let x=reader_ask() |> bind; let unused=0; return (value=x+1) }
    assert((typeinfo typename(readerFast)) == (typeinfo typename(readerSlow)))
    var inscope listFast <- computation(ListBuilder()) { let x=fixed_array(1,2) |> bind; return x+1 }
    var inscope listSlow <- computation(ListBuilder()) { let x=fixed_array(1,2) |> bind; let unused=0; return x+1 }
    assert((typeinfo typename(listFast)) == (typeinfo typename(listSlow)))
    assert(length(listFast)==length(listSlow) && listFast[0]==listSlow[0] && listFast[1]==listSlow[1])
    print("bind_return type checks OK\n")
}

