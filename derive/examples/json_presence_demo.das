options gen2
require ../lib/derive.das
[derive(json=true,validate=true)]
struct Profile {
    name:string
    nickname:$Option<string>
    @json_required=false
    bio:$JsonField<string>
}
[export]
def main() {
    var inscope absent <- derive_from_json("\{\"name\":\"Alice\",\"nickname\":null\}",type<Profile>,"user",true)
    verify(absent.ok && absent.value.nickname is none && absent.value.bio is missing)
    var inscope nul <- derive_from_json("\{\"name\":\"Alice\",\"nickname\":\"Al\",\"bio\":null\}",type<Profile>,"user",true)
    verify(nul.ok && nul.value.nickname is some && nul.value.bio is null_value)
    var inscope present <- derive_from_json("\{\"name\":\"Alice\",\"nickname\":null,\"bio\":\"Hello\"\}",type<Profile>,"user",true)
    verify(present.ok && present.value.bio is present)
    print("{derive_to_json(absent.value)}\n{derive_to_json(nul.value)}\n{derive_to_json(present.value)}\n")
    var inscope bad <- derive_from_json("\{\"name\":\"Alice\",\"typo\":true\}",type<Profile>,"user",true)
    verify(!bad.ok && length(bad.errors)==2)
    for(issue in bad.errors) {print("{issue.path}: {issue.message} [{issue.code}]\n")}
    print("Derive JSON presence demo OK\n")
}
