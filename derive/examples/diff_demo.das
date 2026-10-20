options gen2
require ./diff_model.das
[export]
def main() {
    var inscope before <- diff_before()
    var inscope after <- diff_after(before)
    var inscope changes <- derive_diff(before,after,"game")
    verify(length(changes)==10)
    for(change in changes) {
        print("{change.path}: [{change.kind}] {change.before} -> {change.after}\n")
    }
    print("Derive diff demo OK\n")
}
