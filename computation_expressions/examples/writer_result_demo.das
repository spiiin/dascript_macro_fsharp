options gen2
require ../support/purchase_example.das
[export]
def main() {
    var completed = 0
    let success = purchase(1, 20, completed)
    assert(success.result is ok && (success.result as ok) == "potion")
    assert(success.log == "purchase started\nfind item 1\nchecks passed\n")
    let failed = purchase(1, 5, completed)
    assert(failed.result is error && (failed.result as error) == "insufficient gold")
    assert(failed.log == "purchase started\nfind item 1\n")
    let missing = purchase(99, 20, completed)
    assert(missing.result is error && (missing.result as error) == "item not found")
    assert(missing.log == "purchase started\nfind item 99\n")
    assert(completed == 1)
    print("Success: {success.result as ok}\n{success.log}")
    print("Error: {failed.result as error}\nRetained log:\n{failed.log}")
    print("Completed purchases: {completed}\nwriter/result demo OK\n")
}
