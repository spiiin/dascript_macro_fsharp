options gen2
require ../lib/computation.das
[export]
def main() {
    let values=fixed_array(1,2)
    let result=computation(ResultBuilder()) {for (v,i in values,range(2)) {v+=1}}
}
