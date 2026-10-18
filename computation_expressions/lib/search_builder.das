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

// Own the source; close it before publishing the last permitted solution.
// Nonpositive limits are empty and never step the source.
def search_take(var source:iterator<auto(T)>; limit:int) : iterator<T> {
    return <- generator<T> capture(<-source,copy(limit)) {
        var remaining=limit
        while(remaining>0) {
            var value:T
            var more=false
            try {more=ce_sequence_next_value(source,value)} recover {
                let message="{this_context().last_exception}"
                sequence_close(source)
                panic(message)
            }
            if(!more) {break}
            remaining--
            if(remaining==0) {sequence_close(source)}
            yield value
        }
        sequence_close(source)
        return false
    } finally {ce_sequence_finalize($ {sequence_close(source)})}
}

// Always attempt both closes, even if one finalizer throws.
def ce_search_close_pair(var left:iterator<auto(T)>;var right:iterator<T>) {
    var failure=""
    try {sequence_close(left)} recover {failure="{this_context().last_exception}"}
    try {sequence_close(right)} recover {
        if(failure=="") {failure="{this_context().last_exception}"}
    }
    if(failure!="") {panic(failure)}
}

// Ordered alternatives: exhaust left, then right. Duplicates are retained.
// Both iterator handles are owned immediately, but their bodies remain lazy.
def search_append(var left:iterator<auto(T)>;var right:iterator<T>) : iterator<T> {
    return <- generator<T> capture(<-left,<-right) {
        for(side in range(2)) {
            while(true) {
                var value:T
                var more=false
                try {
                    if(side==0) {more=ce_sequence_next_value(left,value)}
                    else {more=ce_sequence_next_value(right,value)}
                } recover {
                    let message="{this_context().last_exception}"
                    ce_search_close_pair(left,right)
                    panic(message)
                }
                if(!more) {break}
                yield value
            }
            if(side==0) {sequence_close(left)}
        }
        ce_search_close_pair(left,right)
        return false
    } finally {ce_sequence_finalize($ {ce_search_close_pair(left,right)})}
}
