options gen2
require ../support/json_resource_example.das
[export]
def main() {
    var finalized = 0
    let success = computation(WriterResultBuilder()) {
        try_finally($ {
            let value = read_health("\{\"health\":42\}", false) |> bind
            return value
        }, $ { finalized++ })
    }
    let failed = computation(WriterResultBuilder()) {
        try_finally($ {
            let value = read_health("\{\"health\":42\}", true) |> bind
            return value
        }, $ { finalized++ })
    }
    let invalid = read_health("not JSON", false)
    assert(invalid.result is err)
    assert(success.result is ok && (success.result as ok) == 42 && failed.result is err)
    assert(resource_opens == 2 && resource_closes == 2 && finalized == 2)
    print("Success and Error: opened={resource_opens}, closed={resource_closes}, finally={finalized}\n")
    print("resources demo OK\n")
}


