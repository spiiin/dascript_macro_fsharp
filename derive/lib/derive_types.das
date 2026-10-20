options gen2
module derive_types public
require daslib/option public
require daslib/templates_boost
require daslib/templates
require daslib/typemacro_boost
struct JsonNull {}
// Use for optional nullable JSON fields when absence must survive round-trip.
[template_variant(T)]
struct template JsonField {
    missing:void
    null_value:JsonNull
    @safe_when_uninitialized present:T
}



[template(t)]
def json_missing(t:auto(JT)) {return default<$JsonField<JT -const>>}
[template(t)]
def json_null(t:auto(JT)) {
    return variant type<$JsonField<JT -const>>(null_value=JsonNull())
}
def json_present(value:auto(JT)) {
    static_if(typeinfo can_copy(value)) {return variant type<$JsonField<JT -const>>(present=value)}
    else {return variant type<$JsonField<JT -const>>(present <- clone_to_move(value))}
}
def json_move_present(var value:auto(JT)) {
    return variant type<$JsonField<JT -const>>(present <- value)
}
