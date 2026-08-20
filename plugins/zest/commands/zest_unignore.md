---
description: Resume tracking the current folder
---

```bash
sh -s -- command unignore <<'ZEST_RESOLVE'
# Locate zest-grok. Order: plugin-root, user-plugin, installed-plugin, state-launcher.
zest_pick_bin() {
  if [ -e "$ZEST_BIN_DIR/zest-grok" ]; then printf '%s\n' "$ZEST_BIN_DIR/zest-grok"; return 0; fi
  if [ -f "$ZEST_BIN_DIR/zest-grok.cmd" ]; then printf '%s\n' "$ZEST_BIN_DIR/zest-grok.cmd"; return 0; fi
  return 1
}
H=${GROK_HOME:-"$HOME/.grok"}
S=${ZEST_GROK_STATE_DIR:-"$HOME/.grok-zest"}
cli=""
if [ -z "${GROK_PLUGIN_ROOT:-}" ] && [ -f "$S/plugin-root" ]; then
  IFS= read -r GROK_PLUGIN_ROOT < "$S/plugin-root" || true
fi
if [ -z "$cli" ] && [ -n "${GROK_PLUGIN_ROOT:-}" ]; then
  ZEST_BIN_DIR="$GROK_PLUGIN_ROOT/bin"
  cli=$(zest_pick_bin) || true
fi
if [ -z "$cli" ]; then
  ZEST_BIN_DIR="$H/plugins/zest/bin"
  cli=$(zest_pick_bin) || true
fi
if [ -z "$cli" ]; then
  n=$(ls -td "$H/installed-plugins"/zest-* 2>/dev/null | head -n 1) || true
  if [ -n "$n" ]; then ZEST_BIN_DIR="$n/bin"; cli=$(zest_pick_bin) || true; fi
fi
if [ -z "$cli" ]; then
  ZEST_BIN_DIR="$S/bin"
  cli=$(zest_pick_bin) || true
fi
if [ -z "$cli" ]; then
  echo "Zest CLI not found." >&2
  exit 1
fi
for zest_arg in "$@"; do
  if [ "$zest_arg" = "--print" ]; then printf '%s\n' "$cli"; exit 0; fi
done
if [ -x "$cli" ]; then exec "$cli" "$@"; fi
case $cli in *.cmd)
  if command -v cmd.exe >/dev/null 2>&1; then exec cmd.exe //c "$cli" "$@"; fi
  ;;
esac
exec sh "$cli" "$@"
ZEST_RESOLVE
```

Show the complete output to the user.
