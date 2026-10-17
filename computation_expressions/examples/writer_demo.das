options gen2
require ../lib/computation.das

def reward(amount : int) {
    return computation(WriterBuilder()) {
        tell("reward +{amount}\n") |> bind
        return amount
    }
}
[export]
def main() {
    let report = computation(WriterBuilder()) {
        tell("turn started\n") |> bind
        let gold = reward(3) |> bind
        if (gold > 0) { tell("reward accepted\n") |> bind }
        for (i in range(2)) {
            tell("event {i}\n") |> bind
        }
        return gold * 10
    }
    assert(report.value == 30)
    assert(report.log == "turn started\nreward +3\nreward accepted\nevent 0\nevent 1\n")
    print("score={report.value}\n{report.log}")
    print("writer demo OK\n")
}
