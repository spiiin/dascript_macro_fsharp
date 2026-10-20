options gen2
module derive_diff public
require ./derive_runtime.das public
require daslib/rtti

// Diagnostic snapshots, not a typed patch or a persistent serialization format.
struct DiffChange {path:string;kind:string;before:string;after:string}

def diff_path(parent,field:string) : string {
    return parent=="" ? field : parent+"."+field
}
def diff_add(var changes:array<DiffChange>;path,kind,before,after:string) {
    changes |> push(DiffChange(path=path,kind=kind,before=before,after=after))
}
def derive_diff(before,after:auto;root:string="") : array<DiffChange> {
    static_assert(typeinfo typename(before)==typeinfo typename(after),"derive_diff requires matching types")
    var changes:array<DiffChange>
    try {_::derive_diff_into(before,after,root,changes)} recover {
        let message="{this_context().last_exception}"
        delete changes
        panic(message)
    }
    return <- changes
}
def derive_diff_into(before,after:string;path:string;var changes:array<DiffChange>) {
    if(!_::derive_equal(before,after)) {diff_add(changes,path,"changed",_::derive_debug(before),_::derive_debug(after))}
}
def derive_diff_into(before,after:bool;path:string;var changes:array<DiffChange>) {
    if(before!=after) {diff_add(changes,path,"changed",_::derive_debug(before),_::derive_debug(after))}
}
def derive_diff_into(before,after:auto(T);path:string;var changes:array<DiffChange>) {
    static_if(typeinfo typename(before)!=typeinfo typename(after)) {
        static_assert(false,"derive_diff requires matching types")
    } static_elif((typeinfo is_numeric(type<T>) && !typeinfo is_vector(type<T>)) || typeinfo is_enum(type<T>)) {
        if(!_::derive_equal(before,after)) {diff_add(changes,path,"changed",_::derive_debug(before),_::derive_debug(after))}
    } static_elif(typeinfo is_variant(type<T>)) {
        // Validate both tags, including the equal-tag path, before any payload access.
        let beforeCase=derive_variant_name(before)
        let afterCase=derive_variant_name(after)
        if(beforeCase!=afterCase) {
            diff_add(changes,path,"case",_::derive_debug(before),_::derive_debug(after))
            return
        }
        derive_variant_diff(before,after,path,changes)
    } else {
        static_assert(false,"derive_diff: unsupported value; use [derive(diff=true)] on nested structs or provide a derive_diff_into overload")
    }
}
def derive_diff_array(before,after:auto;path:string;var changes:array<DiffChange>) {
    let common=(length(before)<length(after) ? length(before) : length(after))
    for(i in range(common)) {_::derive_diff_into(before[i],after[i],"{path}[{i}]",changes)}
    for(i in range(common,length(before))) {diff_add(changes,"{path}[{i}]","removed",_::derive_debug(before[i]),"")}
    for(i in range(common,length(after))) {diff_add(changes,"{path}[{i}]","added","",_::derive_debug(after[i]))}
}
def derive_diff_into(before,after:array<auto(T)>;path:string;var changes:array<DiffChange>) {
    derive_diff_array(before,after,path,changes)
}
def derive_diff_into(before,after:auto(T)[];path:string;var changes:array<DiffChange>) {
    static_assert(typeinfo typename(before)==typeinfo typename(after),"derive_diff requires matching types")
    derive_diff_array(before,after,path,changes)
}
def derive_diff_into(before,after:$Option<auto(OptionPayload)>;path:string;var changes:array<DiffChange>) {
    if((before is none)!=(after is none)) {
        diff_add(changes,path,"state",_::derive_debug(before),_::derive_debug(after))
    } elif(before is some) {_::derive_diff_into(before as some,after as some,path,changes)}
}
def derive_diff_into(before,after:$JsonField<auto(FieldPayload)>;path:string;var changes:array<DiffChange>) {
    if(variant_index(before)!=variant_index(after)) {
        diff_add(changes,path,"state",_::derive_debug(before),_::derive_debug(after))
    } elif(before is present) {_::derive_diff_into(before as present,after as present,path,changes)}
}
