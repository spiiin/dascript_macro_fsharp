options gen2
require ../lib/computation_macro.das
require ../support/bounded_result_builder.das

// No registration or changes to computation.das are needed.
[export]
def main() {
    var processed=0
    let patrol=computation(BoundedResultBuilder(limit=3)) {
        for (enemy in range(10)) {
            let damage=variant<ok:int;error:string>(ok=enemy+1) |> bind
            processed+=damage
        }
        return processed
    }
    assert(patrol is error && patrol as error=="for budget exhausted" && processed==6)

    var turns=0
    let battle=computation(BoundedResultBuilder(limit=5)) {
        while (turns<3) {
            variant<ok:bool;error:string>(ok=true) |> bind
            turns++
        }
        return turns
    }
    assert(battle is ok && battle as ok==3)
    print("loop protocol demo OK: patrol stopped at budget; battle completed {turns} turns\n")
}
