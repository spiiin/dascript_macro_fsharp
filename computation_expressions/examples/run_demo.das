options gen2
require ../lib/computation_macro.das
require ../support/report_builder.das

def buy(gold:int) {
    return computation(ReportBuilder(title="Buy sword")) {
        let p=result_ok(gold) |> and_bind(result_ok(30)) |> bind
        if (p.first<p.second) { return result_error("Not enough gold",type<int>) |> return_from }
        else { return p.first-p.second }
    }
}
[export]
def main() {
    let bought=buy(50)
    assert(bought is completed && (bought as completed).value==20)
    let denied=buy(10)
    assert(denied is failed && (denied as failed).message=="Not enough gold")
    print("{(bought as completed).title}: gold left {(bought as completed).value}\n")
    print("{(denied as failed).title}: {(denied as failed).message}\n")
    print("run demo OK\n")
}
