options gen2
require ../lib/computation.das
require daslib/rtti
struct Record {a:int; b:int; c:int; d:int; e:int; f:int}
[export]
def main() {
    let baseline=heap_bytes_allocated()
    {
        var inscope records <- computation(SequenceBuilder(type<Record>)) {
            yield Record(a=10,f=60)
            yield Record(a=20,f=70)
        }
        let names=fixed_array("first","second")
        var inscope hp <- [100,200]
        var count=0
        let result=computation(ResultBuilder()) {
            for (record,name,health in records,names,hp) {
                assert(record.a==(count==0 ? 10 : 20))
                assert(record.f==(count==0 ? 60 : 70))
                assert(name==(count==0 ? "first" : "second"))
                health-=record.a
                count++
            }
            return count
        }
        assert(result as ok==2 && hp[0]==90 && hp[1]==180)
    }
    let current=heap_bytes_allocated()
    assert(current==baseline)
    print("zip cursor value checks OK\n")
}
