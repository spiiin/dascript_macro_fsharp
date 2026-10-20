options gen2
require ../lib/derive.das
[derive(equality=false,hash=false,clone=true,validate=true,patch=true)]
struct Invalid {value:int}
[export]
def main() {

}
