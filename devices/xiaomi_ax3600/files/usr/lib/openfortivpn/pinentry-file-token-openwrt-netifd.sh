#!/bin/sh
# Assuan pinentry for OpenFortiVPN using password/OTP files.
# OTP supplied by the existing Raspberry Pi O365 monitor via SSH.
umask 077
interface="${OPENFORTIVPN_INTERFACE:-default}"
password_file="${OPENFORTIVPN_PASSWORD_FILE:-/var/etc/openfortivpn/${interface}.passwd}"
token_file="${OPENFORTIVPN_TOKEN_FILE:-/tmp/openfortivpn-token-${interface}.txt}"
timeout="${OPENFORTIVPN_TOKEN_TIMEOUT:-120}"
waiting_file="${token_file}.waiting"
keyinfo=
prompt=
desc=
respond_secret() {
  # Percent-escape '%': OpenFortiVPN decodes Assuan D strings.
  escaped=$(printf '%s' "$1" | sed 's/%/%25/g')
  printf 'D %s\n' "$escaped"
}
read_password() {
  if [ ! -s "$password_file" ]; then
    printf 'ERR 83886179 Password unavailable\n'
    return
  fi
  password=
  IFS= read -r password < "$password_file" || :
  respond_secret "$password"
}
read_otp() {
  printf 'interface=%s\ntimestamp=%s\ntoken_file=%s\ntimeout=%s\n' \
    "$interface" "$(date '+%Y-%m-%d %H:%M:%S')" "$token_file" "$timeout" > "$waiting_file"
  started=$(date +%s)
  while [ ! -s "$token_file" ]; do
    now=$(date +%s)
    if [ "$((now-started))" -ge "$timeout" ]; then
      rm -f "$waiting_file"
      printf 'ERR 83886179 OTP timeout\n'
      return
    fi
    sleep 1
  done
  token=
  IFS= read -r token < "$token_file" || :
  rm -f "$waiting_file" "$token_file"
  if [ -n "$token" ]; then
    respond_secret "$token"
  else
    printf 'ERR 83886179 OTP empty\n'
  fi
}
trap 'rm -f "$waiting_file"; exit 1' INT TERM
printf 'OK Pinentry ready\n'
while IFS= read -r line; do
  case "$line" in
    SETKEYINFO\ *) keyinfo=${line#SETKEYINFO }; printf 'OK\n' ;;
    SETPROMPT\ *) prompt=${line#SETPROMPT }; printf 'OK\n' ;;
    SETDESC\ *) desc=${line#SETDESC }; printf 'OK\n' ;;
    SETTITLE\ *|OPTION\ *|SETOK\ *|SETCANCEL\ *) printf 'OK\n' ;;
    GETPIN)
      hint=$(printf '%s %s %s' "$keyinfo" "$prompt" "$desc" | tr '[:upper:]' '[:lower:]')
      case "$hint" in
        *otp*|*2fa*|*token*|*two-factor*) read_otp ;;
        *) read_password ;;
      esac
      ;;
    BYE) printf 'OK\n'; exit 0 ;;
    '') ;;
    *) printf 'OK\n' ;;
  esac
done
