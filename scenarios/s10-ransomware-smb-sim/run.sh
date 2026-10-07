#!/usr/bin/env bash
# S10 — Ransomware SMB simulation (pola burst SMB). Kategori: Backdoor.
# SIMULASI perilaku: baca -> "enkripsi" lokal -> tulis .locked -> hapus asli,
# berulang cepat lewat SMB. TANPA payload enkripsi sungguhan & HANYA pada file
# yang dibuat skrip ini sendiri (tidak menyentuh data lab lain).
# Target default: //srv-file/labshare (labadmin). Fase: mana saja (srv-file on).
SCN=S10; ATTACK_CAT=Backdoor; PHASE=any
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../_lib/common.sh"
need_tool smbclient
banner
ensure_up "$SRV_FILE"

N="${1:-40}"                       # jumlah file untuk pola burst
SH="//$SRV_FILE/$SMB_SHARE_LINUX"
AUTH="-U ${LIN_USER}%${LIN_PASS}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
REMDIR="s10sim_$(date -u +%H%M%S)"  # subfolder khusus simulasi di share

smb(){ smbclient "$SH" $AUTH -c "$1" 2>&1; }

mark_start "$SRV_FILE"
echo "== siapkan $N file sintetis di share ($REMDIR) =="
smb "mkdir $REMDIR" >/dev/null 2>&1 || true
for i in $(seq 1 "$N"); do head -c 4096 /dev/urandom > "$WORK/doc_$i.dat"; done
( CMD="cd $REMDIR"; for i in $(seq 1 "$N"); do CMD="$CMD; put $WORK/doc_$i.dat doc_$i.dat"; done; smb "$CMD" ) >/dev/null

echo "== fase 'enkripsi': get -> transform lokal -> put .locked -> del asli (burst) =="
for i in $(seq 1 "$N"); do
  smb "cd $REMDIR; get doc_$i.dat $WORK/g_$i" >/dev/null 2>&1
  # 'enkripsi' simulatif: XOR sederhana via openssl (bukan ransomware nyata)
  openssl enc -aes-128-cbc -pbkdf2 -k simkey -in "$WORK/g_$i" -out "$WORK/g_$i.locked" 2>/dev/null \
    || cp "$WORK/g_$i" "$WORK/g_$i.locked"
  smb "cd $REMDIR; put $WORK/g_$i.locked doc_$i.dat.locked; del doc_$i.dat" >/dev/null 2>&1
done
echo "== bersihkan folder simulasi =="
( CMD="cd $REMDIR"; for i in $(seq 1 "$N"); do CMD="$CMD; del doc_$i.dat.locked"; done; smb "$CMD" ) >/dev/null 2>&1
smb "rmdir $REMDIR" >/dev/null 2>&1 || true
mark_end "$SRV_FILE"
echo "Selesai (burst $N file read+write+delete via SMB = sampel S10)."
