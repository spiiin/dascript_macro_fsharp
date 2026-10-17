options gen2
module identity_builder public
require ./lib/builder_protocol.das public
struct IdentityBuilder {}
def ce_protocol(builder:IdentityBuilder) {return CeValueProtocol()}
def ce_unwrap(builder:IdentityBuilder; source:tuple<value:auto(T)>) : T {return source.value}
def ce_bind(builder:IdentityBuilder; source:tuple<value:auto(T)>; next:block<(item:T):auto(R)>) : R {
    return invoke(next,source.value)
}
def ce_return(builder:IdentityBuilder; value:auto(T)) {return (value=value)}
def ce_zero(builder:IdentityBuilder) {return (value=CeUnit())}
def ce_combine(builder:IdentityBuilder; first:tuple<value:CeUnit>; next:block<():auto(R)>) : R {return invoke(next)}
