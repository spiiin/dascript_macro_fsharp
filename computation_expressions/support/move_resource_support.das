options gen2
module move_resource_support public
require ../lib/computation.das public
struct UploadBuffer {id:int;data:array<int>}
var resources_opened=0
var resources_closed=0
var close_order=""
def acquire_buffer(id:int) {
    var value:UploadBuffer
    value.id=id
    value.data <- [id,20,30]
    resources_opened++
    return <- value
}
def ce_dispose(var value:UploadBuffer) {
    assert(value.id!=0)
    resources_closed++
    close_order+="{value.id}"
    delete value
}
def failed_buffer() : UploadBuffer {panic("acquire failed");return <- UploadBuffer()}
