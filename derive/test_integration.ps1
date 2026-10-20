param([string]$Daslang=$env:DASLANG_EXE,[switch]$Jit,[string]$OutputDirectory=(Join-Path $PSScriptRoot '.work'))
$ErrorActionPreference='Stop'
if(-not $Daslang){$Daslang='C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'}
$destination=Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('integration-'+[guid]::NewGuid().ToString('N'))
& (Join-Path $PSScriptRoot 'export_library.ps1') -Destination $destination
$smoke=@'
options gen2
require ./lib/derive.das
require daslib/rtti
enum Kind {
    Normal
    Special
}
variant Action {idle;text:string}
[derive(validate=true,json=true,clone=true,diff=true,patch=true,builder=true)]
struct Bag {
    @validate_non_empty
    items:array<int>
    @validate_min_length=4
    name:string
    @json_required=false
    nickname:$Option<string>
    @json_required=false
    bio:$JsonField<string>
    @json_required=false
    kind:Kind
    @json_required=false
    action:Action
}
def check() {
    var inscope a:Bag
    var inscope b:Bag
    a.name="bag";b.name="bag"
    var inscope errors <- derive_validate(a,"bag")
    verify(length(errors)==2 && errors[0].path=="bag.items" && errors[1].code=="min_length")
    a.items <- [1,2];b.items <- [1,2]
    a.name="bags";b.name="bags"
    a.kind=Kind.Special;b.kind=Kind.Special
    a.action=Action(text="hello");b.action=Action(text="hello")
    var inscope loaded <- derive_from_json(derive_to_json(a),type<Bag>,"bag",true)
    verify(loaded.ok && derive_equal(a,loaded.value))
    var inscope patchTarget <- derive_clone(loaded.value)
    patchTarget.items[0]=4
    var inscope patch <- derive_make_patch(loaded.value,patchTarget)
    var inscope patched <- derive_apply_patch(loaded.value,patch,"bag")
    verify(patched.ok && (patched.value as some).items[0]==4 && loaded.value.items[0]==1)

    let items=optic("items")
    var inscope snapshot <- a |> optic_get(items)
    snapshot[0]=8
    verify(a.items[0]==1)
    var inscope renamed <- a |> optic_set("name","pack") |> optic_over("name") <| $(name:string) {return name+"s"}
    verify(renamed.name=="packs" && a.name=="bags")
    renamed.items[0]=7
    verify(a.items[0]==1)
    var inscope noNickname <- a |> prism_try_get("nickname.some")
    verify(noNickname is none && (a |> prism_matches("nickname.none")))
    var callbackCalled=false
    var inscope skippedNickname <- a |> prism_over("nickname.some") <| $(name:string) {callbackCalled=true;return name+"!"}
    verify(!callbackCalled && skippedNickname.nickname is none)
    a.nickname=some("Alice")
    var inscope nickname <- a |> prism_try_get("nickname.some")
    verify(nickname is some && (nickname as some)=="Alice")
    var inscope nicknamed <- a |> prism_set("nickname.some","Bob")
    verify((a.nickname as some)=="Alice" && (nicknamed.nickname as some)=="Bob")
    a.nickname=none(type<string>)
    let schema=derive_json_schema(type<Bag>)
    verify(length(schema)>100)
    var inscope draft <- derive_builder(type<Bag>)
    draft |> builder_name("bags")
    draft |> builder_items(a.items)
    var inscope built <- derive_build(draft)
    verify(built.ok && (built.value as some).items[0]==1)
    (built.value as some).items[0]=9
    verify(a.items[0]==1 && draft.data.items[0]==1)

    var inscope malformed <- derive_from_json("\{\"items\":[1,\"bad\"],\"name\":2\}",type<Bag>,"bag")
    verify(!malformed.ok && length(malformed.errors)==2)
    var inscope strict <- derive_from_json("\{\"items\":[1],\"name\":\"bags\",\"extra\":true\}",type<Bag>,"bag",true)
    verify(!strict.ok && length(strict.errors)==1 && strict.errors[0].code=="json_unknown")
    var inscope nullable <- derive_from_json("\{\"items\":[1],\"name\":\"bags\",\"nickname\":null,\"bio\":null\}",type<Bag>,"bag",true)
    verify(nullable.ok && nullable.value.nickname is none && nullable.value.bio is null_value)
    a.name="bag";b.name="bag"

    var inscope copied <- derive_clone(a)
    verify(derive_equal(a,copied))
    copied.items[0]=99
    verify(a.items[0]==1 && copied.items[0]==99)
    var inscope changes <- derive_diff(a,copied,"bag")
    verify(length(changes)==1 && changes[0].path=="bag.items[0]" && changes[0].kind=="changed")

    verify(derive_equal(a,b) && derive_hash(a)==derive_hash(b))
    verify(derive_debug(a)=="Bag\{items=[1, 2], name=\"bag\", nickname=None, bio=Missing, kind=Special, action=text(\"hello\")\}")
}
[export]
def main() {
    check()
    let baseline=heap_bytes_allocated()
    for(i in range(16)) {check();verify(heap_bytes_allocated()==baseline)}
    print("Derive external integration OK\n")
}
'@
$path=Join-Path $destination 'main.das'
[IO.File]::WriteAllText($path,$smoke)
$arguments=@($path,'-no-module-cache')
if($Jit){$arguments+=@('-jit','-jit-no-cache')}
$output=@(& $Daslang @arguments 2>&1 | ForEach-Object {"$_"})
if($LASTEXITCODE -ne 0 -or !($output -join "`n").Contains('Derive external integration OK')) {
    $output|ForEach-Object {Write-Host $_}
    throw 'Derive standalone integration failed'
}
Write-Host 'Derive standalone export verified.'
