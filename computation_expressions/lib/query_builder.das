options gen2
module query_builder public
require ./list_builder.das public
require math
require daslib/rtti
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
def ce_bind(builder:tuple<kind:QueryContext;element:auto(T)>; source:array<auto(U)>; next:block<(row:U):array<T>>) {
    return <- ce_bind(ListBuilder(type<T>),source,next)
}
def ce_bind(builder:tuple<kind:QueryContext;element:auto(T)>; source:auto(U)[]; next:block<(row:U):array<T>>) {
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

// Stable ascending order (descending=true reverses key order, not ties).
// Keys are evaluated exactly once per row, in source order.
def query_order_by(source:auto; key:block<(row:auto(T)):auto(K)>; descending:bool=false) {
    static_assert(typeinfo can_copy(type<T>),"query_order_by requires copyable rows")
    static_assert(typeinfo can_copy(type<K>),"query_order_by requires copyable keys")
    var inscope keys:array<K -const -&>
    var inscope order:array<int>
    var inscope scratch:array<int>
    var inscope rows:array<T -const -&>
    try {
        let count=length(source)
        for(i in range(count)) {keys |> push(invoke(key,source[i]));order |> push(i)}
        scratch.resize(count)
        var width=1
        while(width<count) {
            var start=0
            while(start<count) {
                let middle=start+min(width,count-start)
                let end=middle+min(width,count-middle)
                var left=start
                var right=middle
                for(outIndex in range(start,end)) {
                    var useRight=false
                    if(right<end) {
                        if(left>=middle) {useRight=true}
                        elif(descending) {useRight=keys[order[left]]<keys[order[right]]}
                        else {useRight=keys[order[right]]<keys[order[left]]}
                    }
                    if(useRight) {scratch[outIndex]=order[right];right++}
                    else {scratch[outIndex]=order[left];left++}
                }
                start=end
            }
            for(i in range(count)) {order[i]=scratch[i]}
            if(width>=count-width) {break}
            width*=2
        }
        for(i in range(count)) {rows |> push(source[order[i]])}
    } recover {
        let message="{this_context().last_exception}"
        delete keys;delete order;delete scratch;delete rows
        panic(message)
    }
    return <- rows
}

// Stable groups: first appearance of key, then source order inside each group.
// Equality-based lookup deliberately needs no hash function on user keys.
def query_group_by(source:auto; key:block<(row:auto(T)):auto(K)>) {
    static_assert(typeinfo can_copy(type<T>),"query_group_by requires copyable rows")
    static_assert(typeinfo can_copy(type<K>),"query_group_by requires copyable keys")
    var inscope groups:array<tuple<key:K -const -&;values:array<T -const -&>>>
    try {
        for(i in range(length(source))) {
            let rowKey=invoke(key,source[i])
            var found=-1
            for(j in range(length(groups))) {
                if(groups[j].key==rowKey) {found=j;break}
            }
            if(found<0) {
                var inscope group:tuple<key:K -const -&;values:array<T -const -&>>
                group.key=rowKey
                groups |> emplace(group)
                found=length(groups)-1
            }
            groups[found].values |> push(source[i])
        }
    } recover {ce_list_rethrow(groups)}
    return <- groups
}

// Keep the first row for each key. Keys are evaluated once per input row.
def query_distinct(source:auto; key:block<(row:auto(T)):auto(K)>) {
    static_assert(typeinfo can_copy(type<T>),"query_distinct requires copyable rows")
    static_assert(typeinfo can_copy(type<K>),"query_distinct requires copyable keys")
    var inscope keys:array<K -const -&>
    var inscope rows:array<T -const -&>
    try {
        for(i in range(length(source))) {
            let rowKey=invoke(key,source[i])
            var found=false
            for(j in range(length(keys))) {if(keys[j]==rowKey) {found=true;break}}
            if(!found) {keys |> push(rowKey);rows |> push(source[i])}
        }
    } recover {
        let message="{this_context().last_exception}"
        delete keys;delete rows
        panic(message)
    }
    return <- rows
}

def query_distinct(source:auto) {
    return <- query_distinct(source,$(row:typedecl(source[0]) -const -&) {return row})
}

// Groups contain owning arrays; bind them explicitly by mutable reference.
def ce_unwrap_borrow(builder:tuple<kind:QueryContext;element:auto(T)>; var source:array<auto(U)>) : U& {
    unsafe {return source[0]}
}
def ce_bind(builder:tuple<kind:QueryContext;element:auto(T)>; var source:array<auto(S)>;
            next:block<(var row:auto(U)):auto(R)>) : R {
    return <- ce_bind(ListBuilder(type<T>),source,next)
}

// Block-last overload for source |> query_order_by(true) <| key.
def query_order_by(source:auto; descending:bool; key:block<(row:auto(T)):auto(K)>) {
    return <- query_order_by(source,key,descending)
}
