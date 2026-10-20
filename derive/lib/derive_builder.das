options gen2
module derive_builder public
require ./derive_validation.das public
require daslib/templates
require daslib/typemacro_boost

[template_tuple(T)]
struct template DerivedBuilder {data:T;supplied:table<string;bool>}

[template(t)]
def derive_builder(t:auto(T)) : $DerivedBuilder<T -const -&> {
    unsafe {
        var draft:$DerivedBuilder<T -const -&>
        return <- draft
    }
}

// Empty owning result; constructing it does not execute any Model defaults.
[template(t)]
def derive_builder_empty_result(t:auto(T)) {
    static_if(typeinfo can_copy(type<T>)) {
        return <- (ok=false,value=none(type<T -const -&>),errors <- default<array<ValidationIssue>>)
    } else {
        return <- (ok=false,value <- none(type<T -const -&>),errors <- default<array<ValidationIssue>>)
    }
}
