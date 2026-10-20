options gen2
struct Item {session:int=42}
struct Container {items:Item[1]=default<Item[1]>}
[export]
def main() {
    var value=Container()
    verify(value.items[0].session==42)
    print("Fixed-array defaults OK\n")
}
