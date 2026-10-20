options gen2
require ../examples/collection_validation_model.das
require daslib/rtti
require strings

var trace=""
var throw_at=""
def check_number(value:int;path:string;var errors:array<ValidationIssue>) {
    trace+="{value};"
    if(value<0) {validation_add(errors,path,"negative","number")}
    if(throw_at=="each") {panic("element callback failed")}
}
def number_key(value:int) : int {
    if(throw_at=="key") {panic("key callback failed")}
    return value
}
def check_array(value:array<int>;path:string;var errors:array<ValidationIssue>) {
    validation_add(errors,path,"whole array","array")
    if(throw_at=="field") {panic("field callback failed")}
}
[derive(validate=true)]
struct Numbers {
    @validate_check="check_array"
    @validate_each="check_number"
    @validate_unique_by="number_key"
    values:array<int>
}
[derive(validate=true)]
struct FixedNumbers {
    @validate_each="check_number"
    @validate_unique_by="number_key"
    values:int[3]
}
[derive(validate=true)]
struct NestedNumbers {rows:array<Numbers>}

def check_optional(value:$Option<int>;path:string;var errors:array<ValidationIssue>) {
    if(value is none) {validation_add(errors,path,"required by business rule","optional")}
}
[derive(validate=true)]
struct OptionalNumber {
    @validate_check="check_optional"
    value:$Option<int>
}
var key_calls=0
var fail_owned_key=false
def owned_key(value:int) : array<int> {
    key_calls++
    if(fail_owned_key && key_calls==3) {panic("owned key failed")}
    var inscope result:array<int>
    result |> push(value)
    return <- result
}
[derive(validate=true)]
struct OwnedKeys {
    @validate_unique_by="owned_key"
    values:array<int>
}
def string_key(value:string) : string {return value}
[derive(validate=true)]
struct StringKeys {
    @validate_unique_by="string_key"
    values:string[3]
}
def check() {
    var inscope roster <- invalid_roster()
    var inscope issues <- derive_validate(roster,"game")
    verify(length(issues)==10)
    verify(issues[0].path=="game.title" && issues[0].code=="title")
    verify(issues[1].code=="registered")
    verify(issues[2].path=="game.members[0].id")
    verify(issues[3].path=="game.members[1].id")
    verify(issues[4].path=="game.members[2].id")
    verify(issues[5].path=="game.members[1]" && issues[5].code=="unique")
    verify(find(issues[5].message,"game.members[0]")>=0)
    verify(issues[6].path=="game.members[2]" && issues[6].code=="unique")
    verify(issues[7].path=="game.members[0].name" && issues[7].code=="non_empty")
    verify(issues[8].path=="game.members[0].score" && issues[8].code=="min")
    verify(issues[9].path=="game" && issues[9].code=="roster")
    var inscope json <- derive_from_json(derive_to_json(roster),type<CheckedRoster>,"loaded",true)
    verify(!json.ok && length(json.errors)==10 && json.errors[5].path=="loaded.members[1]")
    var inscope numbers:Numbers
    numbers.values |> push(-1);numbers.values |> push(-1);numbers.values |> push(-1)
    trace=""
    var inscope errs <- derive_validate(numbers)
    verify(trace=="-1;-1;-1;" && length(errs)==6)
    verify(errs[0].path=="values" && errs[1].path=="values[0]" && errs[4].path=="values[1]")
    var inscope appended:array<ValidationIssue>
    validation_add(appended,"existing","retained")
    derive_validate_into(numbers,"n",appended)
    verify(length(appended)==7 && appended[0].path=="existing" && appended[1].path=="n.values")
    var inscope fixed <- derive_validate(FixedNumbers(values=fixed_array(2,2,3)),"fixed")
    verify(length(fixed)==1 && fixed[0].path=="fixed.values[1]")
    var inscope nested:NestedNumbers
    nested.rows |> emplace(numbers)
    var inscope nestedErrors <- derive_validate(nested,"root")
    verify(length(nestedErrors)==6 && nestedErrors[5].path=="root.rows[0].values[2]")
    var inscope empty:Numbers
    var inscope emptyErrors <- derive_validate(empty)
    verify(length(emptyErrors)==1)
    var inscope optional <- derive_validate(OptionalNumber(value=none(type<int>)))
    verify(length(optional)==1 && optional[0].path=="value")
    var inscope present <- derive_validate(OptionalNumber(value=some(5)))
    verify(length(present)==0)
    // A callback exception is propagated; accumulated issues and temporary keys are cleaned.
    for(mode in fixed_array("field","each","key")) {
        throw_at=mode
        var caught=false
        let before=heap_bytes_allocated()
        try {var inscope unused <- derive_validate(nested,"root")} recover {caught=true}
        verify(caught && heap_bytes_allocated()==before && length(nested.rows[0].values)==3)
    }
    throw_at=""
    var inscope owned:OwnedKeys
    owned.values |> push(4);owned.values |> push(5);owned.values |> push(4)
    key_calls=0
    var inscope ownedErrors <- derive_validate(owned,"owned")
    verify(key_calls==3 && length(ownedErrors)==1 && ownedErrors[0].path=="owned.values[2]")
    fail_owned_key=true;key_calls=0
    let beforeKeys=heap_bytes_allocated()
    var caughtKey=false
    try {var inscope unused <- derive_validate(owned)} recover {caughtKey=true}
    verify(caughtKey && key_calls==3 && heap_bytes_allocated()==beforeKeys)
    fail_owned_key=false
    var inscope strings <- derive_validate(StringKeys(values=fixed_array("A","B","A")))
    verify(length(strings)==1 && strings[0].path=="values[2]")
    roster.title="Arena"
    roster.players.resize(2)
    roster.players[0]=CheckedPlayer(id=1,name="Alice",score=1)
    roster.players[1]=CheckedPlayer(id=2,name="Bob",score=2)
    var inscope valid <- derive_validate(roster)
    verify(length(valid)==0)
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive collection validation checks OK\n")
}
