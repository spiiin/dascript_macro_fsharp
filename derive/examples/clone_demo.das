options gen2
require ./clone_model.das
[export]
def main() {
    var inscope original <- clone_game()
    var inscope copy <- derive_clone(original)
    verify(derive_equal(original,copy))
    copy.inventory[0].mods[0]=100
    copy.matrix[0][0]=200
    copy.fixed[0].mods[0]=300
    (copy.option as some).mods[0]=400
    (copy.patch as present).mods[0]=500
    (copy.action as item).mods[0]=600
    verify(original.inventory[0].mods[0]==3)
    verify(original.matrix[0][0]==10)
    verify(original.fixed[0].mods[0]==4)
    verify((original.option as some).mods[0]==6)
    verify((original.patch as present).mods[0]==7)
    verify((original.action as item).mods[0]==8)
    verify(!derive_equal(original,copy))
    print("Original modifier: {original.inventory[0].mods[0]}, copy: {copy.inventory[0].mods[0]}\n")
    print("Derive clone demo OK\n")
}
