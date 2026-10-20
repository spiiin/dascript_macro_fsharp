options gen2
module collection_validation_model public
require ../lib/derive.das public

[derive(validate=true,json=true)]
struct CheckedPlayer {
    id:int
    @validate_non_empty
    name:string
    @validate_min=0
    score:int
}

def check_title(value:string;path:string;var errors:array<ValidationIssue>) {
    if(value!="Arena") {
        validation_add(errors,path,"expected Arena","title")
        validation_add(errors,path,"title is not registered","registered")
    }
}
def check_player_entry(value:CheckedPlayer;path:string;var errors:array<ValidationIssue>) {
    if(value.id<=0) {validation_add(errors,validation_path(path,"id"),"positive id required","player_id")}
}
def player_id(value:CheckedPlayer) : int {return value.id}

[derive(validate=true,json=true,check="check_roster")]
struct CheckedRoster {
    @validate_check="check_title"
    title:string
    @json_name="members"
    @validate_each="check_player_entry"
    @validate_unique_by="player_id"
    players:array<CheckedPlayer>
}
def check_roster(value:CheckedRoster;path:string;var errors:array<ValidationIssue>) {
    if(length(value.players)>2) {validation_add(errors,path,"roster exceeds two players","roster")}
}
def invalid_roster() {
    var inscope roster:CheckedRoster
    roster.players |> push(CheckedPlayer(id=0,name="",score=-1))
    roster.players |> push(CheckedPlayer(id=0,name="B",score=2))
    roster.players |> push(CheckedPlayer(id=0,name="C",score=3))
    return <- roster
}
