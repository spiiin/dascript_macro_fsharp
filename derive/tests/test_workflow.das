options gen2
require ../examples/workflow_model.das
require daslib/rtti
[export]
def main() {
    derive_workflow(false)
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {derive_workflow(false);verify(heap_bytes_allocated()==baseline)}
    print("Derive workflow checks OK\n")
}
