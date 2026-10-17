options gen2
module list_builder public
require ./computation_builders.das public
require daslib/rtti

struct ListContext {}
struct MoveListContext {}
def ListBuilder(unused : type<auto(T)>) {
    static_if (typeinfo can_copy(type<T>)) {
        return (kind=ListContext(), element=default<T -const>)
    } else {
        var marker:T -const -&?
        return (kind=MoveListContext(), element=marker)
    }
}

def ListBuilder() { return ListBuilder(type<int>) }
def ce_zero(builder : tuple<kind : ListContext; element : auto(T)>) : array<T> {
    var inscope values : array<T>
    return <- values
}
def ce_return(builder : tuple<kind : ListContext; element : auto(T)>; value : T) : array<T> {
    var inscope values : array<T>
    values |> push(value)
    return <- values
}
def ce_unwrap(builder : tuple<kind : ListContext; element : auto(T)>; source : auto(U)[]) : U { return source[0] }
def ce_unwrap(builder : tuple<kind : ListContext; element : auto(T)>; source : array<auto(U)>) : U { return source[0] }
def ce_bind(builder : tuple<kind : ListContext; element : auto(T)>; source : auto(U)[];
            next : block<(item : U) : array<T>>) : array<T> {
    var inscope values : array<T>
    try {
        // Indexed traversal avoids leaving a native array iterator locked on panic.
        for (sourceIndex in range(length(source))) {
            let item = source[sourceIndex]
            var inscope part <- invoke(next, item)
            for (value in part) { values |> push(value) }
        }
    } recover {
        let failure = "{this_context().last_exception}"
        delete values
        panic(failure)
    }
    return <- values
}
def ce_bind(builder : tuple<kind : ListContext; element : auto(T)>; source : array<auto(U)>;
            next : block<(item : U) : array<T>>) : array<T> {
    var inscope values : array<T>
    try {
        // Indexed traversal avoids leaving a native array iterator locked on panic.
        for (sourceIndex in range(length(source))) {
            let item = source[sourceIndex]
            var inscope part <- invoke(next, item)
            for (value in part) { values |> push(value) }
        }
    } recover {
        let failure = "{this_context().last_exception}"
        delete values
        panic(failure)
    }
    return <- values
}
def ce_return_from(builder : tuple<kind : ListContext; element : auto(T)>; source : T[]) : array<T> {
    var inscope values : array<T>
    for (value in source) { values |> push(value) }
    return <- values
}
def ce_return_from(builder : tuple<kind : ListContext; element : auto(T)>; source : array<T>) : array<T> {
    var inscope values : array<T>
    for (value in source) { values |> push(value) }
    return <- values
}
def ce_delay(builder : tuple<kind : ListContext; element : auto(T)>; body : block<() : array<T>>) : array<T> {
    return <- invoke(body)
}
def ce_combine(builder : tuple<kind : ListContext; element : auto(T)>; first : array<T>;
               next : block<() : array<T>>) : array<T> {
    var inscope values : array<T>
    for (value in first) { values |> push(value) }
    try {
        var inscope rest <- invoke(next)
        for (value in rest) { values |> push(value) }
    } recover {
        let failure = "{this_context().last_exception}"
        delete values
        panic(failure)
    }
    return <- values
}
def ce_list_append(var accumulated : array<auto(T)>; step : array<T>) {
    for (value in step) { accumulated |> push(value) }
}
def ce_try_finally(builder : tuple<kind : ListContext; element : auto(T)>;
                   body : block<() : array<T>>; cleanup : block<() : void>) : array<T> {
    var inscope values : array<T>
    try { values <- invoke(body) } recover {
        let failure = "{this_context().last_exception}"
        invoke(cleanup)
        panic(failure)
    }
    try { invoke(cleanup) } recover {
        let failure = "{this_context().last_exception}"
        delete values
        panic(failure)
    }
    return <- values
}
def ce_using(builder : tuple<kind : ListContext; element : auto(T)>; resource : auto(U);
             body : block<(item : U) : array<T>>; cleanup : block<(var item : U) : void>) : array<T> {
    var owned = resource
    var inscope values : array<T>
    try { values <- invoke(body, owned) } recover {
        let failure = "{this_context().last_exception}"
        invoke(cleanup, owned)
        panic(failure)
    }
    try { invoke(cleanup, owned) } recover {
        let failure = "{this_context().last_exception}"
        delete values
        panic(failure)
    }
    return <- values
}



// Called from generated recovery without requiring rtti in the user's module.
def ce_list_rethrow(var values : array<auto(T)>) {
    let failure = "{this_context().last_exception}"
    delete values
    panic(failure)
}

def ce_try_with(builder : tuple<kind:ListContext;element:auto(T)>;
                body : block<() : array<T>>; handler : block<(message:string) : array<T>>) : array<T> {
    var inscope values : array<T>
    try { values <- invoke(body) } recover {
        let message = "{this_context().last_exception}"
        return <- invoke(handler, message)
    }
    return <- values
}

def ce_protocol(builder : tuple<kind:ListContext;element:auto(T)>) { return CeCollectProtocol() }
def ce_collect_append(builder : tuple<kind:ListContext;element:auto(T)>;
                      var accumulated : array<T>; step : array<T>) { ce_list_append(accumulated, step) }
def ce_collect_rethrow(builder : tuple<kind:ListContext;element:auto(T)>; var accumulated : array<T>) {
    ce_list_rethrow(accumulated)
}

def ce_list_merge_sources(left, right : auto) {
    var inscope values : array<typedecl(ce_source_pair(left[0], right[0]))>
    for (a in left) {
        for (b in right) { values |> push(ce_source_pair(a,b)) }
    }
    return <- values
}
def ce_merge_sources(builder : tuple<kind:ListContext;element:auto(T)>; left : auto(A)[]; right : auto(B)[]) {
    return <- ce_list_merge_sources(left, right)
}
def ce_merge_sources(builder : tuple<kind:ListContext;element:auto(T)>; left : array<auto(A)>; right : auto(B)[]) {
    return <- ce_list_merge_sources(left, right)
}
def ce_merge_sources(builder : tuple<kind:ListContext;element:auto(T)>; left : auto(A)[]; right : array<auto(B)>) {
    return <- ce_list_merge_sources(left, right)
}
def ce_merge_sources(builder : tuple<kind:ListContext;element:auto(T)>; left : array<auto(A)>; right : array<auto(B)>) {
    return <- ce_list_merge_sources(left, right)
}


// One output array; no singleton arrays from ce_return for individual items.
def ce_list_map(source : auto; mapper : block<(value:auto(U)):auto(T)>) : array<T -const -&> {
    var inscope values : array<T -const -&>
    try {
        for (index in range(length(source))) { values |> push(invoke(mapper, source[index])) }
    } recover {
        let message = "{this_context().last_exception}"
        delete values
        panic(message)
    }
    return <- values
}
def ce_bind_return(builder : tuple<kind:ListContext;element:auto(T)>; source : array<auto(U)>;
                   mapper : block<(value:U):T>) : array<T> { return <- ce_list_map(source, mapper) }
def ce_bind_return(builder : tuple<kind:ListContext;element:auto(T)>; source : auto(U)[];
                   mapper : block<(value:U):T>) : array<T> { return <- ce_list_map(source, mapper) }

// Snapshot each input before mapping, preserving materialized-product semantics
// even when the mapper changes a borrowed input. No array of N*M pairs.
def ce_list_map2(left,right:auto; mapper:block<(pair:tuple<first:auto(A);second:auto(B)>):auto(T)>) : array<T -const -&> {
    var inscope values:array<T -const -&>
    if (length(left)==0 || length(right)==0) { return <- values }
    var inscope leftSnapshot:array<A -const -&>
    var inscope rightSnapshot:array<B -const -&>
    try {
        for (i in range(length(left))) { leftSnapshot |> push(left[i]) }
        for (j in range(length(right))) { rightSnapshot |> push(right[j]) }
        for (i in range(length(leftSnapshot))) {
            for (j in range(length(rightSnapshot))) {
                values |> push(invoke(mapper,ce_source_pair(leftSnapshot[i],rightSnapshot[j])))
            }
        }
    } recover {
        let message="{this_context().last_exception}"
        delete values
        delete rightSnapshot
        delete leftSnapshot
        panic(message)
    }
    return <- values
}

def ce_bind2_return(builder:tuple<kind:ListContext;element:auto(T)>; left:auto(A)[]; right:auto(B)[];
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):T>) : array<T> {
    return <- ce_list_map2(left,right,mapper)
}

def ce_bind2_return(builder:tuple<kind:ListContext;element:auto(T)>; left:auto(A)[]; right:array<auto(B)>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):T>) : array<T> {
    return <- ce_list_map2(left,right,mapper)
}

def ce_bind2_return(builder:tuple<kind:ListContext;element:auto(T)>; left:array<auto(A)>; right:auto(B)[];
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):T>) : array<T> {
    return <- ce_list_map2(left,right,mapper)
}

def ce_bind2_return(builder:tuple<kind:ListContext;element:auto(T)>; left:array<auto(A)>; right:array<auto(B)>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):T>) : array<T> {
    return <- ce_list_map2(left,right,mapper)
}

// Snapshot the grouped sources, then flatten each continuation result.
def ce_list_bind2(left,right:auto; mapper:block<(pair:tuple<first:auto(A);second:auto(B)>):array<auto(T)>>) : array<T> {
    var inscope values:array<T>
    var inscope part:array<T>
    if (length(left)==0 || length(right)==0) { return <- values }
    var inscope leftSnapshot:array<A -const -&>
    var inscope rightSnapshot:array<B -const -&>
    try {
        for (i in range(length(left))) { leftSnapshot |> push(left[i]) }
        for (j in range(length(right))) { rightSnapshot |> push(right[j]) }
        for (i in range(length(leftSnapshot))) {
            for (j in range(length(rightSnapshot))) {
                part <- invoke(mapper,ce_source_pair(leftSnapshot[i],rightSnapshot[j]))
                for (k in range(length(part))) { values |> push(part[k]) }
                delete part
            }
        }
    } recover {
        let message="{this_context().last_exception}"
        delete part
        delete values
        delete rightSnapshot
        delete leftSnapshot
        panic(message)
    }
    return <- values
}

def ce_bind2(builder:tuple<kind:ListContext;element:auto(T)>; left:auto(A)[]; right:auto(B)[];
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):array<T>>) : array<T> {
    return <- ce_list_bind2(left,right,mapper)
}

def ce_bind2(builder:tuple<kind:ListContext;element:auto(T)>; left:auto(A)[]; right:array<auto(B)>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):array<T>>) : array<T> {
    return <- ce_list_bind2(left,right,mapper)
}

def ce_bind2(builder:tuple<kind:ListContext;element:auto(T)>; left:array<auto(A)>; right:auto(B)[];
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):array<T>>) : array<T> {
    return <- ce_list_bind2(left,right,mapper)
}

def ce_bind2(builder:tuple<kind:ListContext;element:auto(T)>; left:array<auto(A)>; right:array<auto(B)>;
                    mapper:block<(pair:tuple<first:A -const -&;second:B -const -&>):array<T>>) : array<T> {
    return <- ce_list_bind2(left,right,mapper)
}

// Move-only output: each bind owns its input; callbacks borrow individual items.
def ce_protocol(builder:tuple<kind:MoveListContext;element:auto(T)?>) {return CeOwnedProtocol()}
def ce_zero(builder:tuple<kind:MoveListContext;element:auto(T)?>) : array<T> {
    var inscope values:array<T>
    return <- values
}
def ce_return_move(builder:tuple<kind:MoveListContext;element:auto(T)?>; var value:T) : array<T> {
    var inscope values:array<T>
    values |> emplace <| value
    return <- values
}
def ce_return(builder:tuple<kind:MoveListContext;element:auto(T)?>; value:T) : array<T> {
    concept_assert(false,"move-only List: use return <- or yield <-")
    return <- ce_zero(builder)
}
def ce_unwrap(builder:tuple<kind:MoveListContext;element:auto(T)?>; var source:array<auto(U)>) : U& {unsafe {return source[0]}}
def ce_unwrap(builder:tuple<kind:MoveListContext;element:auto(T)?>; var source:auto(U)[]) : U& {unsafe {return source[0]}}
def ce_move_list_append(var values:array<auto(T)>; var part:array<T>) {
    for (i in range(length(part))) {values |> emplace <| part[i]}
}
def ce_bind(builder:tuple<kind:MoveListContext;element:auto(T)?>; var source:array<auto(S)>;
            next:block<(var item:auto(U)):auto(R)>) : R {
    var inscope owner <- source
    var inscope values:array<T>
    var inscope part:array<T>
    try {
        for(i in range(length(owner))) {
            part <- invoke(next,owner[i])
            ce_move_list_append(values,part)
            delete part
        }
    } recover {
        let message="{this_context().last_exception}"
        delete part
        delete values
        delete owner
        panic(message)
    }
    return <- values
}
def ce_return_from(builder:tuple<kind:MoveListContext;element:auto(T)?>; var source:array<T>) {return <- source}
def ce_delay(builder:tuple<kind:MoveListContext;element:auto(T)?>; body:block<():array<T>>) {return <- invoke(body)}
def ce_combine(builder:tuple<kind:MoveListContext;element:auto(T)?>; var first:array<T>;
               next:block<():array<T>>) : array<T> {
    var inscope values <- first
    var inscope rest:array<T>
    try {rest <- invoke(next);ce_move_list_append(values,rest)} recover {
        let message="{this_context().last_exception}"
        delete rest
        delete values
        panic(message)
    }
    return <- values
}
def ce_collect_append(builder:tuple<kind:MoveListContext;element:auto(T)?>; var values,step:array<T>) {ce_move_list_append(values,step)}
def ce_collect_rethrow(builder:tuple<kind:MoveListContext;element:auto(T)?>; var values:array<T>) {ce_list_rethrow(values)}
def ce_loop_failed(builder:tuple<kind:MoveListContext;element:auto(T)?>; values:array<T>) {return false}
def ce_merge_sources(builder:tuple<kind:MoveListContext;element:auto(T)?>; left,right:auto) {
    concept_assert(typeinfo can_copy(left[0]) && typeinfo can_copy(right[0]),"move-only List: and_bind Cartesian product requires copyable input elements")
    return <- ce_list_merge_sources(left,right)
}

def ce_try_finally(builder : tuple<kind : MoveListContext; element : auto(T)?>;
                   body : block<() : array<T>>; cleanup : block<() : void>) : array<T> {
    var inscope values : array<T>
    try { values <- invoke(body) } recover {
        let failure = "{this_context().last_exception}"
        invoke(cleanup)
        panic(failure)
    }
    try { invoke(cleanup) } recover {
        let failure = "{this_context().last_exception}"
        delete values
        panic(failure)
    }
    return <- values
}

def ce_using(builder : tuple<kind : MoveListContext; element : auto(T)?>; resource : auto(U);
             body : block<(item : U) : array<T>>; cleanup : block<(var item : U) : void>) : array<T> {
    var owned = resource
    var inscope values : array<T>
    try { values <- invoke(body, owned) } recover {
        let failure = "{this_context().last_exception}"
        invoke(cleanup, owned)
        panic(failure)
    }
    try { invoke(cleanup, owned) } recover {
        let failure = "{this_context().last_exception}"
        delete values
        panic(failure)
    }
    return <- values
}

def ce_try_with(builder : tuple<kind:MoveListContext;element:auto(T)?>;
                body : block<() : array<T>>; handler : block<(message:string) : array<T>>) : array<T> {
    var inscope values : array<T>
    try { values <- invoke(body) } recover {
        let message = "{this_context().last_exception}"
        return <- invoke(handler, message)
    }
    return <- values
}

// Opt-in consuming input with `var item & = source |> bind`, including maps
// from owning items to ordinary copyable values.
def ce_unwrap_borrow(builder:tuple<kind:ListContext;element:auto(T)>; var source:array<auto(U)>) : U& {unsafe {return source[0]}}
def ce_bind(builder:tuple<kind:ListContext;element:auto(T)>; var source:array<auto(S)>;
            next:block<(var item:auto(U)):auto(R)>) : R {
    var inscope owner <- source
    var inscope values:array<T>
    var inscope part:array<T>
    try {
        for(i in range(length(owner))) {
            part <- invoke(next,owner[i])
            ce_move_list_append(values,part)
            delete part
        }
    } recover {
        let message="{this_context().last_exception}"
        delete part
        delete values
        delete owner
        panic(message)
    }
    return <- values
}

def ce_return_move(builder:tuple<kind:ListContext;element:auto(T)>; var value:T) : array<T> {
    var inscope values:array<T>
    values |> emplace(value)
    return <- values
}
def ce_unwrap_borrow(builder:tuple<kind:ListContext;element:auto(T)>; var source:auto(U)[]) : U& {unsafe {return source[0]}}

def ce_bind(builder:tuple<kind:ListContext;element:auto(T)>; var source:auto(S)[];
            next:block<(var item:auto(U)):auto(R)>) : R {
    var inscope owner:array<S>
    for(i in range(length(source))) {owner |> emplace(source[i])}
    try {return <- ce_bind(builder,owner,next)} recover {ce_owned_source_rethrow(owner)}
    return <- default<R>
}

def ce_bind(builder:tuple<kind:MoveListContext;element:auto(T)?>; var source:auto(S)[];
            next:block<(var item:auto(U)):auto(R)>) : R {
    var inscope owner:array<S>
    for(i in range(length(source))) {owner |> emplace(source[i])}
    try {return <- ce_bind(builder,owner,next)} recover {ce_owned_source_rethrow(owner)}
    return <- default<R>
}

def ce_return_from(builder:tuple<kind:MoveListContext;element:auto(T)?>; var source:T[]) : array<T> {
    var inscope values:array<T>
    for(i in range(length(source))) {values |> emplace(source[i])}
    return <- values
}

// A single output buffer for linear copyable bind chains or a consuming map.
def ce_collect_sink(builder:tuple<kind:ListContext;element:auto(T)>) {return ce_collect_sink_protocol(type<T>)}
def ce_collect_sink(builder:tuple<kind:MoveListContext;element:auto(T)?>) {return ce_collect_sink_protocol(type<T>)}

def ce_collect_into(builder:auto; body:block<(var output:array<auto(T)>):CeUnit>) : array<T> {
    var inscope output:array<T>
    try {invoke(body,output)} recover {ce_list_rethrow(output)}
    return <- output
}
def ce_collect_emit(builder:tuple<kind:ListContext;element:auto(T)>; var output:array<T>; value:T) {
    output |> push(value)
}
def ce_collect_emit_move(builder:tuple<kind:MoveListContext;element:auto(T)?>; var output:array<T>; var value:T) {
    output |> emplace(value)
}
def private ce_list_visit_copy(source:auto; body:auto) : CeUnit {
    for(i in range(length(source))) {
        let snapshot=source[i]
        invoke(body,snapshot)
    }
    return CeUnit()
}
def ce_collect_each(builder:tuple<kind:ListContext;element:auto(T)>; var output:array<T>;
                    source:auto(U)[]; body:block<(item:U):CeUnit>) : CeUnit {
    return ce_list_visit_copy(source,body)
}
def ce_collect_each(builder:tuple<kind:ListContext;element:auto(T)>; var output:array<T>;
                    source:array<auto(U)>; body:block<(item:U):CeUnit>) : CeUnit {
    return ce_list_visit_copy(source,body)
}
// This path is restricted to one consuming bind by the macro. On panic, output
// is destroyed before remaining input, matching the original owning ce_bind.
def private ce_list_visit_owned(var output:array<auto(T)>; var source:array<auto(S)>; body:auto) : CeUnit {
    var inscope owner <- source
    try {
        for(i in range(length(owner))) {invoke(body,owner[i])}
    } recover {
        let message="{this_context().last_exception}"
        delete output
        delete owner
        panic(message)
    }
    return CeUnit()
}
def ce_collect_each_move(builder:tuple<kind:ListContext;element:auto(T)>; var output:array<T>;
                    var source:array<auto(S)>; body:block<(var item:auto(U)):CeUnit>) : CeUnit {
    return ce_list_visit_owned(output,source,body)
}
def ce_collect_each_move(builder:tuple<kind:MoveListContext;element:auto(T)?>; var output:array<T>;
                    var source:array<auto(S)>; body:block<(var item:auto(U)):CeUnit>) : CeUnit {
    return ce_list_visit_owned(output,source,body)
}
def ce_collect_each_move(builder:tuple<kind:ListContext;element:auto(T)>; var output:array<T>;
                    var source:auto(S)[]; body:block<(var item:auto(U)):CeUnit>) : CeUnit {
    var inscope owner:array<S>
    for(i in range(length(source))) {owner |> emplace(source[i])}
    try {return ce_list_visit_owned(output,owner,body)} recover {ce_owned_source_rethrow(owner)}
    return CeUnit()
}
def ce_collect_each_move(builder:tuple<kind:MoveListContext;element:auto(T)?>; var output:array<T>;
                    var source:auto(S)[]; body:block<(var item:auto(U)):CeUnit>) : CeUnit {
    var inscope owner:array<S>
    for(i in range(length(source))) {owner |> emplace(source[i])}
    try {return ce_list_visit_owned(output,owner,body)} recover {ce_owned_source_rethrow(owner)}
    return CeUnit()
}
