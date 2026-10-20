options gen2
options max_infer_passes=1024
options stack=524288
require ../lib/reactivex.das
require daslib/rtti
var released:int[130]
var closed:int[128]
var cleanupOrder:array<int>
var completed=0
var nextCount=0
struct Owned {
    id:int
    values:array<int>
    def finalize {if(!empty(values)) {released[id]++;delete values}}
}
def owned(id:int) {return <- Owned(id=id,values <- [42])}

def checks() {
    for(mode in range(6)) {
        for(i in range(130)) {released[i]=0}
        for(i in range(128)) {closed[i]=0}
        clear(cleanupOrder);completed=0;nextCount=0
        var held:array<typedecl(rx_sink_marker(type<int>)) -const -&>
        var selected=0
        var selectorData <- owned(129)
        var source <- rx_range(0,128) |> rx_flat_map(unsafe(@ capture(&held,&selected,<-selectorData,copy(mode)) (n:int) {
            verify(selectorData.values[0]==42);selected++
            return <- rx_create(type<int>,unsafe(@ capture(&held,copy(mode),copy(n)) (sink:typedecl(rx_sink_marker(type<int>))) {
                held |> emplace(rx_sink_clone(sink))
                var data <- owned(n)
                rx_sink_add_cleanup(sink,@ capture(<-data,copy(mode),copy(n)) () {
                    verify(data.values[0]==42)
                    closed[n]++;cleanupOrder |> push(n)
                    if(mode==2 && n==63) {panic("cleanup failed")}
                } finally {delete data})
                if(mode==3 && n==63) {panic("connect failed")}
                if(mode==4) {rx_sink_complete(sink);verify(closed[n]==1 && released[n]==1)}
            }))
        } finally {delete selectorData}))
        var sub <- rx_subscription()
        var observerData <- owned(128)
        var caught=false
        try {
            unsafe {
                rx_subscribe_with(sub,source,@ capture(&held,&sub,<-observerData,copy(mode)) (n:int) {
                    verify(observerData.values[0]==42);nextCount++
                    if(mode==0 && n==63) {
                        rx_sink_complete(held[63]) // erase the middle while its callback is active
                        verify(closed[63]==1 && released[63]==1 && observerData.values[0]==42)
                    } elif(mode==1) {
                        delete sub
                        verify(observerData.values[0]==42 && length(cleanupOrder)==128)
                    } elif(mode==2) {rx_unsubscribe(sub)}
                } finally {delete observerData},@(s:string) {panic("unexpected on_error")},@(){completed++})
            }
        } recover {caught=true}
        delete source
        verify(caught==(mode==3))
        let expected=mode==3 ? 64 : 128
        verify(selected==expected && length(held)==expected)
        if(mode==0) {
            verify(!rx_is_closed(sub) && empty(cleanupOrder))
            rx_sink_next(held[63],63)
            verify(nextCount==1 && cleanupOrder[0]==63 && completed==0)
            rx_sink_next(held[63],999);rx_sink_complete(held[63])
            verify(nextCount==1 && length(cleanupOrder)==1)
            for(i in range(128)) {let index=127-i;if(index!=63) {rx_sink_complete(held[index])}}
        } elif(mode==1 || mode==2) {
            verify(!rx_is_closed(sub) && empty(cleanupOrder))
            caught=false
            try {rx_sink_next(held[63],63)} recover {caught=true}
            verify(caught==(mode==2) && nextCount==1)
            // A failing child cleanup must not prevent closing later siblings.
            for(i in range(128)) {verify(cleanupOrder[i]==i)}
        } elif(mode==5) {
            var moved <- sub
            verify(rx_is_closed(sub) && !rx_is_closed(moved))
            delete sub
            verify(empty(cleanupOrder))
            delete moved
            verify(rx_is_closed(moved))
        }
        verify(rx_is_closed(sub) && length(cleanupOrder)==expected)
        verify(completed==((mode==0 || mode==4) ? 1 : 0))
        for(i in range(128)) {verify(closed[i]==(i<expected ? 1 : 0) && released[i]==(i<expected ? 1 : 0))}
        let previous=nextCount
        for(sink in held) {rx_sink_next(sink,999);rx_sink_complete(sink);rx_sink_error(sink,"stale")}
        verify(nextCount==previous && length(cleanupOrder)==expected)
        delete sub;delete held
        verify(released[128]==1 && released[129]==1)
        for(i in range(128)) {verify(closed[i]==(i<expected ? 1 : 0) && released[i]==(i<expected ? 1 : 0))}
    }
    delete cleanupOrder
    // Native loop flags must not skip struct finalizers on unsubscribe.
    for(i in range(130)) {released[i]=0}
    for(i in range(8)) {
        var inscope gate <- rx_subject(type<int>)
        var view <- rx_clone(gate);var data <- owned(i)
        var inscope source <- rx_just(1) |> rx_concat_map(@ capture(<-view,<-data) (n:int) {
            verify(data.values[0]==42);return <- rx_clone(view)
        } finally {delete view;delete data})
        var inscope sub <- rx_subscribe(source,@(n:int){},@(s:string){panic(s)},@(){})
        verify(rx_subscriber_count(gate)==1)
        if(i==3) {break}
        continue
    }
    for(i in range(8)) {verify(released[i]==(i<4 ? 1 : 0))}
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(4)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX child/control owner lifetime tests OK\n")
}
