options gen2
require ../examples/enum_variant_model.das
require daslib/rtti
require strings

def check() {
    var inscope config <- derive_from_json("\{\"role\":\"Mage\",\"commands\":[\{\"case\":\"idle\"\},\{\"case\":\"move\",\"value\":\{\"x\":1,\"y\":2,\"values\":[3,4]\}\},\{\"case\":\"text\",\"value\":\"hello\"\},\{\"case\":\"batch\",\"value\":[\{\"x\":5,\"y\":6,\"values\":[]\}]\},\{\"case\":\"nullable\",\"value\":null\}],\"optional\":\{\"case\":\"idle\"\},\"patch\":\{\"case\":\"text\",\"value\":\"patch\"\}\}",type<CommandConfig>,"game",true)
    verify(config.ok && config.value.role==CharacterRole.Mage && length(config.value.commands)==5)
    verify(config.value.commands[0] is idle && config.value.commands[1] is move && config.value.commands[2] as text=="hello")
    verify((config.value.commands[1] as move).note=="new" && length((config.value.commands[1] as move).values)==2)
    verify(config.value.commands[4] as nullable is none)
    var inscope again <- derive_from_json(derive_to_json(config.value),type<CommandConfig>,"game",true)
    verify(again.ok && derive_equal(config.value,again.value) && derive_hash(config.value)==derive_hash(again.value))
    verify(find(derive_debug(config.value),"move(")>=0)
    var inscope alias <- derive_from_json("\"Wizard\"",type<CharacterRole>)
    verify(alias.ok && alias.value==CharacterRole.Mage && derive_to_json(alias.value)=="\"Mage\"")
    var inscope wide <- derive_from_json("\"High\"",type<WideRole>)
    var inscope largest <- derive_from_json("\"Max\"",type<WideRole>)
    verify(wide.ok && uint64(wide.value)==9223372036854775808ul && derive_to_json(wide.value)=="\"High\"")
    verify(largest.ok && uint64(largest.value)==18446744073709551615ul && derive_to_json(largest.value)=="\"Max\"")
    var inscope small <- derive_from_json("\"Negative\"",type<SmallRole>)
    var inscope signedValue <- derive_from_json("\"Negative\"",type<SignedRole>)
    var inscope fixedEnums <- derive_from_json("[\"Mage\",\"Rogue\"]",type<CharacterRole[2]>)
    verify(small.ok && int(small.value)==-7 && derive_to_json(small.value)=="\"Negative\"")
    verify(signedValue.ok && int64(signedValue.value)==-9007199254740993l && derive_to_json(signedValue.value)=="\"Negative\"")
    verify(fixedEnums.ok && fixedEnums.value[1]==CharacterRole.Rogue)
    var inscope nested <- derive_from_json("\{\"case\":\"inner\",\"value\":\{\"case\":\"text\",\"value\":\"nested\"\}\}",type<NestedCommand>,"action",true)
    verify(nested.ok && nested.value as inner as text=="nested")
    var inscope nestedAgain <- derive_from_json(derive_to_json(nested.value),type<NestedCommand>,"action",true)
    verify(nestedAgain.ok && derive_equal(nested.value,nestedAgain.value))
    var inscope enumBad <- derive_from_json("\"mage\"",type<CharacterRole>,"role")
    var inscope numeric <- derive_from_json("10",type<CharacterRole>,"role")
    verify(!enumBad.ok && enumBad.errors[0].code=="json_enum" && !numeric.ok && numeric.errors[0].code=="json_type")
    var inscope bad <- derive_from_json("\{\"role\":\"Unknown\",\"commands\":[\{\"case\":\"missing\"\},\{\"case\":3\},\{\"value\":0\},\{\"case\":\"move\"\},\{\"case\":\"idle\",\"value\":null\},\{\"case\":\"text\",\"value\":9\}]\}",type<CommandConfig>,"game",true)
    verify(!bad.ok && length(bad.errors)==7)
    verify(bad.errors[0].code=="json_enum" && bad.errors[1].path=="game.commands[0].case" && bad.errors[1].code=="json_variant")
    verify(bad.errors[4].path=="game.commands[3].value" && bad.errors[5].code=="json_variant_payload")
    sum_hook_calls=0
    var inscope strictBad <- derive_from_json("\{\"case\":\"move\",\"extra\":1,\"value\":\{\"x\":-1,\"y\":0,\"values\":[],\"typo\":true\}\}",type<GameCommand>,"action",true)
    verify(!strictBad.ok && length(strictBad.errors)==2 && sum_hook_calls==0)
    verify(strictBad.errors[0].path=="action.extra" && strictBad.errors[1].path=="action.value.typo")
    var inscope relaxed <- derive_from_json("\{\"case\":\"text\",\"value\":\"ok\",\"extra\":1\}",type<GameCommand>)
    verify(relaxed.ok)
    var inscope invalid <- derive_from_json("\{\"case\":\"batch\",\"value\":[\{\"x\":-1,\"y\":0,\"values\":[]\},\{\"x\":-2,\"y\":0,\"values\":[]\}]\}",type<GameCommand>,"action",true)
    verify(!invalid.ok && length(invalid.errors)==2 && invalid.errors[0].path=="action.value[0].x" && invalid.errors[1].path=="action.value[1].x")
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive JSON enum variant checks OK\n")
}
