# vhs tape for the verify-gate demo GIF.
# Render from the repo root:  vhs demo/demo.tape
Output demo/verify-gate.gif

Set Shell bash
Set FontSize 16
Set Width 1000
Set Height 600
Set Padding 16
Set TypingSpeed 35ms
Set Theme "Catppuccin Mocha"

Hide
Type "source demo/scene.sh"
Enter
Sleep 1.5s
Show

Sleep 1.5s

Type `agent_says "Refactored the parser — done, all tests pass ✅"`
Sleep 500ms
Enter
Sleep 5s

Type "run_tests"
Sleep 500ms
Enter
Sleep 4s

Type `agent_says "Refactored the parser — done, all tests pass ✅"`
Sleep 500ms
Enter
Sleep 4.5s
