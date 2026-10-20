options gen2
options max_infer_passes=1024
options stack=262144
require ../lib/reactivex.das
require daslib/rtti
var released:int[5]
var trace=""
struct Owned {
    id:int
    values:array<int>
    def finalize {if(!empty(values)) {released[id]++;delete values}}
}
def owned(id:int) {return <- Owned(id=id,values <- [42])}

def checks() {
    // Retain closed inner sinks across subsequent children. Their callbacks
    // still own run/child storage, but must not emit or keep cleanup active.
    for(mode in range(6)) {
        for(i in range(5)) {released[i]=0}
        trace=""
        var held:array<typedecl(rx_sink_marker(type<int>)) -const -&>
        var selected=0;var cleaned=0
        var selectorData <- owned(0)
        var source <- rx_range(1,3) |> rx_concat_map(unsafe(@ capture(&held,&selected,&cleaned,<-selectorData) (n:int) {
            verify(selectorData.values[0]==42 && cleaned==n-1)
            if(n>1) {verify(released[n-1]==1)}
            selected++;trace+="s{n};"
            return <- rx_create(type<int>,unsafe(@ capture(&held,&cleaned,copy(n)) (sink:typedecl(rx_sink_marker(type<int>))) {
                held |> emplace(rx_sink_clone(sink))
                var data <- owned(n)
                rx_sink_add_cleanup(sink,unsafe(@ capture(&cleaned,<-data,copy(n)) () {
                    verify(data.values[0]==42);cleaned++;trace+="d{n};"
                } finally {delete data}))
            }))
        } finally {delete selectorData}))
        var sub <- rx_subscription()
        var observerData <- owned(4)
        unsafe {
            rx_subscribe_with(sub,source,@ capture(&held,&sub,<-observerData,copy(mode)) (n:int) {
                verify(observerData.values[0]==42);trace+="n{n};"
                if(mode==1) {delete sub;verify(observerData.values[0]==42);trace+="after;"}
                if(mode==3) {panic("next failed")}
                if(mode==5 && n==10) {
                    rx_sink_complete(held[0])
                    rx_sink_next(held[0],999) // stale callback, including during reentry
                    rx_sink_next(held[1],20)
                    verify(observerData.values[0]==42);trace+="after;"
                }
            } finally {delete observerData},@ capture(copy(mode)) (s:string) {
                verify(s=="inner failed");trace+="error;"
                if(mode==4) {panic("error failed")}
            },@(){trace+="done;"})
        }
        delete source
        verify(selected==1 && cleaned==0 && trace=="s1;")
        var caught=false
        try {
            rx_sink_next(held[0],10)
            if(mode==0 || mode==5) {
                if(mode==0) {rx_sink_complete(held[0]);rx_sink_next(held[1],20)}
                rx_sink_next(held[0],999)
                rx_sink_complete(held[0]) // duplicate completion cannot affect child 2
                rx_sink_complete(held[1])
                rx_sink_next(held[2],30);rx_sink_complete(held[2])
            } elif(mode==2 || mode==4) {rx_sink_error(held[0],"inner failed")}
        } recover {caught=true}
        verify(caught==(mode==3 || mode==4))
        if(mode!=1) {verify(rx_is_closed(sub))}
        verify(cleaned==selected && selected==((mode==0 || mode==5) ? 3 : 1))
        if(mode==0) {verify(trace=="s1;n10;d1;s2;n20;d2;s3;n30;d3;done;")}
        elif(mode==1) {verify(trace=="s1;n10;d1;after;")}
        elif(mode==3) {verify(trace=="s1;n10;d1;")}
        elif(mode==5) {verify(trace=="s1;n10;d1;s2;after;n20;d2;s3;n30;d3;done;")}
        else {verify(trace=="s1;n10;d1;error;")}
        let previous=trace
        for(sink in held) {rx_sink_next(sink,999);rx_sink_complete(sink);rx_sink_error(sink,"stale")}
        verify(trace==previous)
        delete sub;delete held
        verify(released[0]==1 && released[4]==1)
        for(i in range(1,4)) {verify(released[i]==(i<=selected ? 1 : 0))}
    }
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(5)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX concat_map inner ownership tests OK\n")
}
