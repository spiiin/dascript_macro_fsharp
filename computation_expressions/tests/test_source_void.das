options gen2
require ../lib/computation.das
struct BadSource {}
def ce_source(builder:ResultBuilder; source:BadSource) {}
[export]
def main() {let value=computation(ResultBuilder()) {let n=BadSource() |> bind;return n};print("{value}")}
