options gen2
module query_builder public
require ./list_builder.das public
struct QueryContext {_ce_marker:uint8}
def QueryBuilder(unused:type<auto(T)>) {
    static_assert(typeinfo can_copy(type<T>),"QueryBuilder requires copyable rows")
    return (kind=QueryContext(),element=default<T -const>)
}
def QueryBuilder() {return QueryBuilder(type<int>)}
def ce_protocol(builder:tuple<kind:QueryContext;element:auto(T)>) {return CeCollectProtocol()}
def ce_zero(builder:tuple<kind:QueryContext;element:auto(T)>) {return <- ce_zero(ListBuilder(type<T>))}
def ce_return(builder:tuple<kind:QueryContext;element:auto(T)>; value:T) {return <- ce_return(ListBuilder(type<T>),value)}
def ce_unwrap(builder:tuple<kind:QueryContext;element:auto(T)>; source:auto) {return ce_unwrap(ListBuilder(type<T>),source)}
def ce_bind(builder:tuple<kind:QueryContext;element:auto(T)>; source:auto; next:block<(row:auto(U)):array<T>>) {
    return <- ce_bind(ListBuilder(type<T>),source,next)
}
def ce_return_from(builder:tuple<kind:QueryContext;element:auto(T)>; source:auto) {return <- ce_return_from(ListBuilder(type<T>),source)}
def ce_delay(builder:tuple<kind:QueryContext;element:auto(T)>; body:block<():array<T>>) {return <- invoke(body)}
def ce_combine(builder:tuple<kind:QueryContext;element:auto(T)>; first:array<T>; next:block<():array<T>>) {
    return <- ce_combine(ListBuilder(type<T>),first,next)
}
def ce_collect_append(builder:tuple<kind:QueryContext;element:auto(T)>; var accumulated:array<T>; step:array<T>) {ce_list_append(accumulated,step)}
def ce_collect_rethrow(builder:tuple<kind:QueryContext;element:auto(T)>; var accumulated:array<T>) {ce_list_rethrow(accumulated)}
def ce_merge_sources(builder:tuple<kind:QueryContext;element:auto(T)>; left,right:auto) {return <- ce_list_merge_sources(left,right)}
def ce_try_finally(builder:tuple<kind:QueryContext;element:auto(T)>; body:block<():array<T>>; cleanup:block<():void>) {
    return <- ce_try_finally(ListBuilder(type<T>),body,cleanup)
}
def ce_try_with(builder:tuple<kind:QueryContext;element:auto(T)>; body:block<():array<T>>; handler:block<(message:string):array<T>>) {
    return <- ce_try_with(ListBuilder(type<T>),body,handler)
}
def ce_using(builder:tuple<kind:QueryContext;element:auto(T)>; resource:auto(U); body:block<(row:U):array<T>>; cleanup:block<(var row:U):void>) {
    return <- ce_using(ListBuilder(type<T>),resource,body,cleanup)
}
// where as a CE step: skip the remaining continuation for rejected rows.
def query_where(accept:bool) {
    var inscope rows:array<CeUnit>
    if(accept) {rows |> push(CeUnit())}
    return <- rows
}
// Collection operators are ordinary pipes, also usable outside CE.
def query_where(source:auto; predicate:block<(row:auto(T)):bool>) {
    var inscope rows:array<T -const -&>
    try {
        for(i in range(length(source))) {if(invoke(predicate,source[i])) {rows |> push(source[i])}}
    } recover {ce_list_rethrow(rows)}
    return <- rows
}
def query_select(source:auto; project:block<(row:auto(T)):auto(U)>) {
    var inscope rows:array<U -const -&>
    try {
        for(i in range(length(source))) {rows |> push(invoke(project,source[i]))}
    } recover {ce_list_rethrow(rows)}
    return <- rows
}
// Stable inner equijoin: outer left order, then right order; duplicates retained.
def query_join(left,right:auto; leftKey:block<(row:auto(L)):auto(K)>; rightKey:block<(row:auto(R)):K>) {
    var inscope rows:array<tuple<first:L -const -&;second:R -const -&>>
    try {
        for(i in range(length(left))) {
            let key=invoke(leftKey,left[i])
            for(j in range(length(right))) {
                if(key==invoke(rightKey,right[j])) {rows |> push(ce_source_pair(left[i],right[j]))}
            }
        }
    } recover {ce_list_rethrow(rows)}
    return <- rows
}
