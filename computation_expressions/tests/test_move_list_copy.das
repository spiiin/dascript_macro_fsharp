options gen2
require ../support/move_collection_support.das
[export]
def main() {var inscope values <- computation(ListBuilder(type<Loot>)) {yield loot(1)}}
