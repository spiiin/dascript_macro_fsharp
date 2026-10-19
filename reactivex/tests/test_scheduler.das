options gen2
options max_infer_passes=1024
require ../lib/rx_scheduler.das
require daslib/rtti
var trace=""
var released=0
def action(text:string) {
    var data:array<int>;data <- [42]
    return <- @ capture(<-data,copy(text)) () {verify(data[0]==42);trace+=text} finally {delete data;released++}
}
def checks() {
    trace=""
    var inscope clock <- rx_virtual_scheduler()
    let before=released
    rx_schedule(clock,10,action("a"))
    let cancelled=rx_schedule(clock,5,action("x"))
    rx_schedule(clock,10,action("b"))
    verify(rx_cancel(clock,cancelled) && !rx_cancel(clock,cancelled) && released==before+1)
    verify(rx_advance_to(clock,9)==0 && trace=="")
    verify(rx_advance_to(clock,10)==2 && trace=="ab" && released==before+3)
    var next <- rx_scheduler_clone(clock)
    rx_schedule(clock,0,@ capture(<-next) () {rx_schedule(next,0,action("d"));trace+="c"} finally {delete next})
    verify(rx_advance_by(clock,0)==2 && trace=="abcd")
    rx_schedule(clock,5,action("e"));rx_schedule(clock,10,action("f"))
    verify(rx_advance_to(clock,30,1)==1 && rx_now_ms(clock)==15)
    verify(rx_advance_to(clock,30)==1 && rx_now_ms(clock)==30 && trace=="abcdef")
    let beforeInvalid=released
    var invalid=false
    try {rx_schedule(clock,-1,action("never"))} recover {invalid=true}
    verify(invalid && released==beforeInvalid+1)
    invalid=false
    try {rx_schedule(clock,9223372036854775807l,action("never"))} recover {invalid=true}
    verify(invalid && released==beforeInvalid+2)
    var caught=false
    try {rx_advance_to(clock,29)} recover {caught=true}
    verify(caught)
    var recursive <- rx_scheduler_clone(clock)
    rx_schedule(clock,0,@ capture(<-recursive) () {rx_advance_by(recursive,0)} finally {delete recursive})
    caught=false
    try {rx_advance_by(clock,0)} recover {caught=true}
    verify(caught)
    rx_schedule(clock,0,action("g"))
    verify(rx_advance_by(clock,0)==1 && trace=="abcdefg")
    rx_schedule(clock,100,action("never"),@(){trace+="close"})
    rx_scheduler_close(clock)
    verify(rx_pending_count(clock)==0 && trace=="abcdefgclose")
    // Pumped time runs late actions at the supplied clock sample.
    var inscope real <- rx_scheduler(100)
    var view <- rx_scheduler_clone(real)
    rx_schedule(real,5,@ capture(<-view) () {verify(rx_now_ms(view)==120)} finally {delete view})
    verify(rx_tick(real,120)==1)
    // Retained descriptors do not keep a deleted primary scheduler running.
    var owner <- rx_virtual_scheduler()
    var inscope lease <- rx_scheduler_clone(owner)
    rx_schedule(owner,1,action("never"),@(){trace+="!"})
    delete owner
    verify(rx_scheduler_closed(lease) && rx_pending_count(lease)==0 && trace=="abcdefgclose!")
    var inscope failing <- rx_virtual_scheduler()
    rx_schedule(failing,1,action("never"),@(){panic("close hook failed")})
    rx_schedule(failing,1,action("never"),@(){trace+="last;"})
    caught=false
    try {rx_scheduler_close(failing)} recover {caught=true}
    verify(caught && rx_scheduler_closed(failing) && rx_pending_count(failing)==0 && trace=="abcdefgclose!last;")
    var inscope idle <- rx_virtual_scheduler()
    let oldReleased=released
    let guard=rx_on_scheduler_close(idle,action("never"))
    verify(rx_pending_count(idle)==0 && rx_close_listener_count(idle)==1)
    verify(rx_cancel(idle,guard) && released==oldReleased+1 && rx_close_listener_count(idle)==0)
    rx_on_scheduler_close(idle,action("idle;"))
    rx_scheduler_close(idle)
    verify(rx_close_listener_count(idle)==0 && released==oldReleased+2)
    rx_on_scheduler_close(idle,action("late;")) // closed registration runs immediately.
    verify(trace=="abcdefgclose!last;idle;late;" && released==oldReleased+3)
}
[export]
def main() {
    checks()
    let baseline=heap_bytes_allocated()
    for(i in range(10)) {checks()}
    verify(heap_bytes_allocated()==baseline)
    print("ReactiveX scheduler checks OK\n")
}
