# zieht den PLIP-/CIA-Verdrahtungsblock woertlich aus minimig.v (kein Nachbau)
import sys
s = open(sys.argv[1]).read()
a = s.index("`ifdef ENABLE_PLIP\n// ---- virtual parallel port")
b = s.index("assign fdd_step_n = _step;") + len("assign fdd_step_n = _step;")
open(sys.argv[2], "w").write(s[a:b] + "\n")
