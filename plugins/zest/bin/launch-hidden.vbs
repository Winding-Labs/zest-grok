' Launch a program hidden and detached (no console flash). Args: <exe> [args...]
Dim args, cmd, i
Set args = WScript.Arguments
cmd = ""
For i = 0 To args.Count - 1
  If i > 0 Then cmd = cmd & " "
  cmd = cmd & """" & args(i) & """"
Next
CreateObject("WScript.Shell").Run cmd, 0, False
