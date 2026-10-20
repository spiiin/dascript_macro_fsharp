options gen2
require ../lib/derive.das
[derive(debug=false,equality=false,hash=false,json=true)]
struct Invalid {

value:table<string;int>
}
[export]
def main() {}
