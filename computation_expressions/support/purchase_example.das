options gen2
module purchase_example public
require ../lib/computation.das public
struct ShopItem { name : string; price : int }

def find_item(id : int) {
    return computation(WriterResultBuilder()) {
        tell("find item {id}\n") |> bind
        if (id == 1) { return ShopItem(name="potion", price=10) }
        else { return result_error("item not found", type<ShopItem>) |> return_from }
    }
}
def check_balance(balance, price : int) : $Result<CeUnit;string> {
    if (balance < price) { return variant type<$Result<CeUnit;string>>(err="insufficient gold") }
    return ce_zero(ResultBuilder())
}
def purchase(id, balance : int; var completed : int&) {
    return computation(WriterResultBuilder()) {
        tell("purchase started\n") |> bind
        let item = find_item(id) |> bind
        check_balance(balance, item.price) |> bind
        tell("checks passed\n") |> bind
        completed++
        return item.name
    }
}


