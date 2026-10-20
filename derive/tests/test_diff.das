options gen2
require ../examples/diff_model.das
require daslib/rtti

[derive(diff=true,json=true,equality=false,hash=false)]
struct DiffFields {
    @json_name="external"
    renamed:int
    @json_skip
    skipped:int
}
[derive(diff=true)]
struct EmptyDiff {}
[derive(diff=true,clone=true)]
struct DiffMatrix {rows:array<array<DiffItem>>;fixed:DiffItem[2]}

def detached_changes() : array<DiffChange> {
    var inscope before <- diff_before()
    var inscope after <- diff_after(before)
    return <- derive_diff(before,after,"game")
}
def check() {
    var inscope before <- diff_before()
    var inscope after <- diff_after(before)
    var inscope changes <- derive_diff(before,after,"game")
    verify(length(changes)==10)
    let paths=fixed_array("game.title","game.stats.health","game.items[0].count","game.items[1]","game.removed[1]","game.fixed[1]","game.option.health","game.patch","game.action.value.health","game.nested.value")
    let kinds=fixed_array("changed","changed","changed","added","removed","changed","changed","state","changed","case")
    for(i in range(length(changes))) {verify(changes[i].path==paths[i] && changes[i].kind==kinds[i])}
    verify(changes[0].before=="\"Arena\"" && changes[0].after=="\"New Arena\"")
    verify(changes[1].before=="100" && changes[1].after=="75")
    verify(changes[3].before=="" && changes[3].after=="DiffItem\{id=2, count=1\}")
    verify(changes[4].before=="8" && changes[4].after=="")
    verify(changes[7].before=="Missing" && changes[7].after=="Null")
    verify(before.stats.health==100 && after.stats.health==75 && length(before.items)==1 && length(after.items)==2)
    var inscope repeated <- derive_diff(before,after,"game")
    for(i in range(length(changes))) {
        verify(changes[i].path==repeated[i].path && changes[i].kind==repeated[i].kind && changes[i].before==repeated[i].before && changes[i].after==repeated[i].after)
    }
    var inscope identical <- derive_diff(before,before)
    verify(length(identical)==0)
    var inscope clone <- derive_clone(before)
    var inscope equivalent <- derive_diff(before,clone)
    verify(length(equivalent)==0)
    var inscope appended:array<DiffChange>
    diff_add(appended,"existing","changed","old","new")
    derive_diff_into(before,after,"",appended)
    verify(length(appended)==11 && appended[0].path=="existing" && appended[1].path=="title")
    // The result keeps only diagnostic strings, not borrowed array elements.
    delete before;delete after
    verify(changes[3].after=="DiffItem\{id=2, count=1\}")
    var inscope detached <- detached_changes()
    verify(length(detached)==10 && detached[1].before=="100")
    var inscope reverseSource:array<int>
    reverseSource <- [10,11,12]
    var inscope empty:array<int>
    var inscope removed <- derive_diff(reverseSource,empty)
    var inscope added <- derive_diff(empty,reverseSource)
    verify(length(removed)==3 && length(added)==3)
    for(i in range(3)) {verify(removed[i].kind=="removed" && added[i].kind=="added" && removed[i].path=="[{i}]" && added[i].path=="[{i}]")}
    var inscope a:array<int>;a <- [1,2]
    var inscope b:array<int>;b <- [0,1,2]
    var inscope shifted <- derive_diff(a,b,"a")
    verify(length(shifted)==3 && shifted[0].path=="a[0]" && shifted[1].path=="a[1]" && shifted[2].kind=="added")
    var inscope fixed <- derive_diff(fixed_array(1,2,3),fixed_array(3,2,1),"fixed")
    verify(length(fixed)==2 && fixed[0].path=="fixed[0]" && fixed[1].path=="fixed[2]")
    var inscope matrix:DiffMatrix
    var row:array<DiffItem>;row |> push(DiffItem(id=1,count=2));matrix.rows |> emplace(row)
    var inscope matrixCopy <- derive_clone(matrix)
    matrixCopy.rows[0][0].count=3;matrixCopy.fixed[1].count=4
    var inscope matrixChanges <- derive_diff(matrix,matrixCopy,"m")
    verify(length(matrixChanges)==2 && matrixChanges[0].path=="m.rows[0][0].count" && matrixChanges[1].path=="m.fixed[1].count")
    var inscope fields <- derive_diff(DiffFields(),DiffFields(renamed=1,skipped=2))
    verify(length(fields)==2 && fields[0].path=="renamed" && fields[1].path=="skipped")
    var inscope emptyStruct <- derive_diff(EmptyDiff(),EmptyDiff())
    verify(length(emptyStruct)==0)
    var inscope scalar <- derive_diff(1,2)
    verify(length(scalar)==1 && scalar[0].path=="" && scalar[0].before=="1" && scalar[0].after=="2")
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(32)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive diff checks OK\n")
}
