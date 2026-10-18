options gen2
module search_builder public
require ./sequence_builder.das public
require daslib/rtti
struct SearchContext {_ce_marker:uint8}
def SearchBuilder(unused:type<auto(T)>) {
    static_assert(typeinfo can_copy(type<T>),"SearchBuilder requires copyable solutions")
    return (kind=SearchContext(),element=default<T -const>)
}
def SearchBuilder() {return SearchBuilder(type<int>)}
def ce_protocol(builder:tuple<kind:SearchContext;element:auto(T)>) {return ce_sequence_protocol(type<T>)}
def ce_sequence_run(builder:tuple<kind:SearchContext;element:auto(T)>; var source:iterator<T>) {
    return <- ce_sequence_protect(source)
}
// Empty source prunes only this branch of the depth-first search.
def search_guard(accept:bool) {
    return <- generator<CeUnit> capture(copy(accept)) {
        if(accept) {yield CeUnit()}
        return false
    }
}
// Explicit scoped cut: keep the first solution of this source, close its rest.
// Deliberately not a global Prolog cut: surrounding choices still backtrack.
def search_once(var source:iterator<auto(T)>) : iterator<T> {
    return <- generator<T> capture(<-source) {
        var value:T
        var more=false
        try {more=ce_sequence_next_value(source,value)} recover {
            let message="{this_context().last_exception}"
            sequence_close(source)
            panic(message)
        }
        sequence_close(source)
        if(more) {yield value}
        return false
    } finally {ce_sequence_finalize($ {sequence_close(source)})}
}
def search_cut(var source:iterator<auto(T)>) {return <- search_once(source)}

// Explicit consuming source for dynamic arrays, including temporary literals.
def search_choose(var values:array<auto(T)>) : iterator<T> {
    static_assert(typeinfo can_copy(type<T>),"SearchBuilder requires copyable choices")
    return <- generator<T> capture(<-values) {
        for(i in range(length(values))) {yield values[i]}
        return false
    } finally {delete values}
}
