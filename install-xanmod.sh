#!/usr/bin/env bash
#
# install-xanmod.sh — авто-установщик ядра XanMod
# Сам определяет: ОС/кодовое имя, архитектуру, уровень x86-64 (v1..v4),
# тип виртуализации, Secure Boot — и ставит подходящий пакет ядра.
#
# Подходит для дедиков и KVM/VPS на Debian 12/13 и Ubuntu.
# НЕ работает на контейнерах (OpenVZ/LXC) — там ядро общее с хостом.
#
# Использование (под root; если не root — добавь sudo):
#   ./install-xanmod.sh                 # МЕНЮ всех веток (main/lts/rt/edge), потом вопрос про ребут
#   ./install-xanmod.sh --list          # показать доступные ядра под эту ОС и выйти
#   ./install-xanmod.sh --branch rt     # сразу нужную ветку, без меню
#   ./install-xanmod.sh --yes           # без вопросов, рекомендованная ветка (массовый прогон, БЕЗ ребута)
#   ./install-xanmod.sh --yes --reboot  # массовый прогон + сразу перезагрузить
#   ./install-xanmod.sh --upgrade       # перед ядром сделать полный apt upgrade всех пакетов
#   ./install-xanmod.sh --no-bbr        # не трогать sysctl (не включать BBR+fq)
#   ./install-xanmod.sh --dry-run       # показать список + что будет сделано, ничего не ставя
#
#   ветки: auto (меню) | main | lts | rt | edge
#   Репозиторий — по кодовому имени релиза. На Debian 12 (bookworm) XanMod
#   публикует только lts; на Debian 13 (trixie) и Ubuntu — main/lts/rt.
#
# Запуск с гита одной строкой (под root):
#   с МЕНЮ выбора ветки (БЕЗ --yes):
#     curl -fsSL https://raw.githubusercontent.com/TeeqzyRU/xanmod-installer/main/install-xanmod.sh | bash
#   массово на ноду (рекомендованная ветка, сразу ребут):
#     curl -fsSL https://raw.githubusercontent.com/TeeqzyRU/xanmod-installer/main/install-xanmod.sh | bash -s -- --yes --reboot
#
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────
#  Цвета и логирование
# ──────────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_YLW=$'\033[1;33m'
  C_BLU=$'\033[0;34m'; C_BOLD=$'\033[1m'; C_RST=$'\033[0m'
else
  C_RED=''; C_GRN=''; C_YLW=''; C_BLU=''; C_BOLD=''; C_RST=''
fi
info() { printf '%s[*]%s %s\n' "$C_BLU" "$C_RST" "$*"; }
ok()   { printf '%s[✓]%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YLW" "$C_RST" "$*"; }
die()  { printf '%s[✗] %s%s\n' "$C_RED" "$*" "$C_RST" >&2; exit 1; }

# ──────────────────────────────────────────────────────────────────────────
#  Аргументы
# ──────────────────────────────────────────────────────────────────────────
BRANCH="auto"        # auto|main|lts|rt|edge  (auto = показать меню/рекомендовать)
VERSION="1.0.0"
ASSUME_YES=0
ENABLE_BBR=1
DRY_RUN=0
FORCE_SB=0
LIST_ONLY=0
REBOOT=0             # --reboot: перезагрузить в конце без вопроса
DO_UPGRADE=0         # --upgrade: сделать полный apt upgrade перед установкой

while [ $# -gt 0 ]; do
  case "$1" in
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --branch=*) BRANCH="${1#*=}"; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    --no-bbr) ENABLE_BBR=0; shift ;;
    --bbr) ENABLE_BBR=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --list) LIST_ONLY=1; shift ;;
    --reboot) REBOOT=1; shift ;;
    --upgrade) DO_UPGRADE=1; shift ;;
    --force-secureboot) FORCE_SB=1; shift ;;
    -V|--version) echo "install-xanmod.sh v$VERSION"; exit 0 ;;
    -h|--help)
      awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$0"; exit 0 ;;
    *) die "Неизвестный аргумент: $1 (см. --help)" ;;
  esac
done

case "$BRANCH" in
  auto|main|lts|rt|edge) ;;
  *) die "Ветка должна быть: auto|main|lts|rt|edge (получено: '$BRANCH')" ;;
esac

run() { # выполнить или показать (dry-run)
  if [ "$DRY_RUN" -eq 1 ]; then printf '   %s# %s%s\n' "$C_YLW" "$*" "$C_RST"; else eval "$*"; fi
}

# ──────────────────────────────────────────────────────────────────────────
#  0. root
# ──────────────────────────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || die "Запусти от root (sudo $0 $*)"

echo
printf '%s┌─────────────────────────────────────────────┐%s\n' "$C_BOLD" "$C_RST"
printf '%s│     XanMod kernel — авто-установщик %-8s │%s\n' "$C_BOLD" "v$VERSION" "$C_RST"
printf '%s└─────────────────────────────────────────────┘%s\n' "$C_BOLD" "$C_RST"
echo

# ──────────────────────────────────────────────────────────────────────────
#  1. ОС и кодовое имя (Debian/Ubuntu, apt)
# ──────────────────────────────────────────────────────────────────────────
[ -r /etc/os-release ] || die "Нет /etc/os-release — ОС не определить"
# shellcheck disable=SC1091
. /etc/os-release

OS_ID="${ID:-unknown}"
OS_LIKE="${ID_LIKE:-}"
CODENAME="${VERSION_CODENAME:-}"
[ -n "$CODENAME" ] && [ "$CODENAME" = "n/a" ] && CODENAME=""

# fallback на lsb_release, если в os-release нет кодового имени
if [ -z "$CODENAME" ] && command -v lsb_release >/dev/null 2>&1; then
  CODENAME="$(lsb_release -sc 2>/dev/null || true)"
fi

is_apt=0
case "$OS_ID" in debian|ubuntu) is_apt=1 ;; esac
case "$OS_LIKE" in *debian*|*ubuntu*) is_apt=1 ;; esac
command -v apt-get >/dev/null 2>&1 || is_apt=0

[ "$is_apt" -eq 1 ] || die "XanMod ставится только на Debian/Ubuntu (apt). У тебя: ${PRETTY_NAME:-$OS_ID}"
[ -n "$CODENAME" ] || die "Не удалось определить кодовое имя релиза (нужно для репозитория XanMod)"

ok "ОС: ${PRETTY_NAME:-$OS_ID}  (codename: $CODENAME)"

# Codename-репозиторий публикуется только для поддерживаемых релизов.
# (на Debian 12/bookworm XanMod публикует только ветку lts — меню покажет само)
case "$CODENAME" in
  bullseye|buster|focal|bionic|stretch|xenial)
    die "Релиз '$CODENAME' репозиторием XanMod не поддерживается (нужен Debian 12+/Ubuntu 24.04+)" ;;
esac

# ──────────────────────────────────────────────────────────────────────────
#  2. Архитектура — только x86-64 (amd64)
# ──────────────────────────────────────────────────────────────────────────
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ok "Архитектура: $ARCH" ;;
  aarch64|arm64|armv7l|armv6l)
    die "Архитектура $ARCH (ARM) не поддерживается — XanMod собирается только под amd64" ;;
  i?86)
    die "Архитектура $ARCH (32-bit) не поддерживается — нужен 64-bit (amd64)" ;;
  *) die "Неизвестная/неподдерживаемая архитектура: $ARCH" ;;
esac

# ──────────────────────────────────────────────────────────────────────────
#  3. Виртуализация — контейнеры отсекаем (общее ядро с хостом)
# ──────────────────────────────────────────────────────────────────────────
VIRT="none"
if command -v systemd-detect-virt >/dev/null 2>&1; then
  VIRT="$(systemd-detect-virt 2>/dev/null || echo none)"
elif [ -f /proc/user_beancounters ]; then
  VIRT="openvz"
fi

case "$VIRT" in
  openvz|lxc|lxc-libvirt|docker|podman|systemd-nspawn|wsl|rkt)
    die "Это контейнер ($VIRT) — ядро общее с хостом, своё ядро установить нельзя.
        XanMod ставится только на дедик или полноценную виртуалку (KVM/Xen-HVM/VMware и т.п.)." ;;
  none)        info "Виртуализация: bare-metal (дедик)" ;;
  kvm|qemu)    info "Виртуализация: KVM/QEMU — ок" ;;
  *)           info "Виртуализация: $VIRT — ставим (полное ядро поддерживается)" ;;
esac

# ──────────────────────────────────────────────────────────────────────────
#  4. Secure Boot — XanMod не подписан ключом MS, с включённым SB не загрузится
# ──────────────────────────────────────────────────────────────────────────
sb_state="disabled"
if command -v mokutil >/dev/null 2>&1; then
  mokutil --sb-state 2>/dev/null | grep -qi enabled && sb_state="enabled"
elif [ -e /sys/firmware/efi ]; then
  sbf=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
  if [ -e "$sbf" ]; then
    [ "$(od -An -t u1 "$sbf" 2>/dev/null | awk '{print $NF}')" = "1" ] && sb_state="enabled"
  fi
fi

if [ "$sb_state" = "enabled" ]; then
  if [ "$FORCE_SB" -eq 1 ]; then
    warn "Secure Boot ВКЛЮЧЁН — продолжаю по --force-secureboot, но ядро может не загрузиться!"
  else
    die "Secure Boot включён. Ядро XanMod не подписано — система откатится на старое ядро.
        Отключи Secure Boot в BIOS/UEFI и запусти снова (или --force-secureboot на свой риск)."
  fi
else
  info "Secure Boot: выключен — ок"
fi

# ──────────────────────────────────────────────────────────────────────────
#  5. Уровень микроархитектуры x86-64 (v1..v4) — по флагам CPU
#     (та же логика, что в официальном check_x86-64_psabi.sh)
# ──────────────────────────────────────────────────────────────────────────
CPU_FLAGS=" $(grep -m1 '^flags' /proc/cpuinfo | cut -d: -f2-) "
hasflag() { case "$CPU_FLAGS" in *" $1 "*) return 0;; *) return 1;; esac; }
have_all() { for f in "$@"; do hasflag "$f" || return 1; done; return 0; }

PSABI=1
have_all cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3 && PSABI=2
[ "$PSABI" -eq 2 ] && have_all avx avx2 bmi1 bmi2 f16c fma abm movbe xsave && PSABI=3
[ "$PSABI" -eq 3 ] && have_all avx512f avx512bw avx512cd avx512dq avx512vl && PSABI=4

CPU_MODEL="$(grep -m1 '^model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
ok "CPU: ${CPU_MODEL:-unknown}"
ok "Поддержка набора инструкций: x86-64-v$PSABI"

# ──────────────────────────────────────────────────────────────────────────
#  6. Базовые зависимости
# ──────────────────────────────────────────────────────────────────────────
need_pkgs=""
command -v wget >/dev/null 2>&1 || need_pkgs="$need_pkgs wget"
command -v gpg  >/dev/null 2>&1 || need_pkgs="$need_pkgs gpg"
[ -f /etc/ssl/certs/ca-certificates.crt ] || need_pkgs="$need_pkgs ca-certificates"

if [ -n "$need_pkgs" ]; then
  info "Доустанавливаю зависимости:$need_pkgs"
  run "apt-get update -qq"
  run "DEBIAN_FRONTEND=noninteractive apt-get install -y$need_pkgs"
fi

# Известный баг установщика XanMod: ругается, если нет /etc/sysctl.conf
[ -f /etc/sysctl.conf ] || run "touch /etc/sysctl.conf"

# ──────────────────────────────────────────────────────────────────────────
#  7. Ключ, репозиторий и pin (идемпотентно — перезаписываем каждый раз)
# ──────────────────────────────────────────────────────────────────────────
KEYRING=/etc/apt/keyrings/xanmod-archive-keyring.gpg
SRCLIST=/etc/apt/sources.list.d/xanmod-release.list
PINFILE=/etc/apt/preferences.d/xanmod

# Репозиторий XanMod работает по кодовому имени релиза (trixie/bookworm/noble/…)
SUITE="$CODENAME"

info "Подключаю репозиторий XanMod (суит: $SUITE)…"
run "mkdir -p /etc/apt/keyrings"
run "wget -qO- https://dl.xanmod.org/archive.key | gpg --dearmor -o '$KEYRING'"
run "echo 'deb [signed-by=$KEYRING] http://deb.xanmod.org $SUITE main' > '$SRCLIST'"

# Pin: из репо XanMod ставим/обновляем ТОЛЬКО ядра (*xanmod*).
# Остальное (iproute2, gamemode и пр., которые лежат в releases-суите)
# берём из дистрибутива — чтобы ничего системного не перетянулось.
if [ "$DRY_RUN" -eq 0 ]; then
  cat > "$PINFILE" <<'EOF'
Package: *xanmod*
Pin: origin "deb.xanmod.org"
Pin-Priority: 500

Package: *
Pin: origin "deb.xanmod.org"
Pin-Priority: 100
EOF
else
  printf '   %s# создать pin %s (только ядра из XanMod)%s\n' "$C_YLW" "$PINFILE" "$C_RST"
fi

# Обновляем индекс ТОЛЬКО по репо XanMod (быстро + ловим недоступность суита)
if [ "$DRY_RUN" -eq 0 ]; then
  if ! apt-get update -o Dir::Etc::sourcelist="$SRCLIST" \
        -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 2>/tmp/xanmod_apt.err; then
    cat /tmp/xanmod_apt.err >&2 || true
    rm -f "$SRCLIST" "$PINFILE"
    die "Репозиторий XanMod (суит '$SUITE') недоступен (система не сломана — источник убран)."
  fi
fi
ok "Репозиторий подключён"

# ──────────────────────────────────────────────────────────────────────────
#  8. Сбор ВСЕХ доступных вариантов ядра под эту ОС и CPU + выбор
# ──────────────────────────────────────────────────────────────────────────
pkg_exists() { [ -n "$(apt-cache madison "$1" 2>/dev/null)" ]; }

prefix_for() {
  case "$1" in
    main) echo "linux-xanmod" ;;
    lts)  echo "linux-xanmod-lts" ;;
    rt)   echo "linux-xanmod-rt" ;;
    edge) echo "linux-xanmod-edge" ;;
  esac
}
desc_for() {
  case "$1" in
    main) echo "стабильная, свежее ядро — обычный выбор" ;;
    lts)  echo "LTS — макс. стабильность, для прода/DKMS (NVIDIA/ZFS)" ;;
    rt)   echo "real-time (PREEMPT_RT) — низкие задержки" ;;
    edge) echo "edge — самое новое mainline-ядро" ;;
  esac
}

# Для каждой ветки берём максимальный доступный уровень <= PSABI.
# Параллельные массивы: ветка / пакет / уровень.
AVAIL_BR=(); AVAIL_PKG=(); AVAIL_V=()
if [ "$DRY_RUN" -eq 0 ]; then
  info "Смотрю, какие ядра доступны в репозитории…"
  for br in main lts rt edge; do
    pfx="$(prefix_for "$br")"; v="$PSABI"
    while [ "$v" -ge 1 ]; do
      cand="${pfx}-x64v${v}"
      if pkg_exists "$cand"; then
        AVAIL_BR+=("$br"); AVAIL_PKG+=("$cand"); AVAIL_V+=("$v"); break
      fi
      v=$((v-1))
    done
  done
  [ "${#AVAIL_PKG[@]}" -gt 0 ] || die "В репозитории нет ядер XanMod для '$CODENAME' (уровень <= v$PSABI)"
else
  for br in main lts rt edge; do
    AVAIL_BR+=("$br"); AVAIL_PKG+=("$(prefix_for "$br")-x64v$PSABI"); AVAIL_V+=("$PSABI")
  done
fi

# Рекомендованный вариант: main, иначе lts, иначе первый доступный.
REC_IDX=0
for i in "${!AVAIL_BR[@]}"; do
  if [ "${AVAIL_BR[$i]}" = "main" ]; then REC_IDX=$i; break; fi
done
if [ "${AVAIL_BR[$REC_IDX]}" != "main" ]; then
  for i in "${!AVAIL_BR[@]}"; do
    if [ "${AVAIL_BR[$i]}" = "lts" ]; then REC_IDX=$i; break; fi
  done
fi

print_list() {
  printf '%sДоступные ядра XanMod для %s (CPU: x86-64-v%s):%s\n' "$C_BOLD" "$CODENAME" "$PSABI" "$C_RST"
  local i mark
  for i in "${!AVAIL_BR[@]}"; do
    mark=""; [ "$i" -eq "$REC_IDX" ] && mark="  ${C_GRN}← рекомендую${C_RST}"
    printf '  %s%s)%s %-5s %-25s %s%s\n' "$C_BOLD" "$((i+1))" "$C_RST" \
      "${AVAIL_BR[$i]}" "${AVAIL_PKG[$i]}" "$(desc_for "${AVAIL_BR[$i]}")" "$mark"
  done
}

# --list: показать доступное и выйти
if [ "$LIST_ONLY" -eq 1 ]; then echo; print_list; echo; exit 0; fi

# ── Какой вариант ставим ──
SEL_IDX=-1
if [ "$BRANCH" != "auto" ]; then
  # ветка задана флагом
  for i in "${!AVAIL_BR[@]}"; do
    if [ "${AVAIL_BR[$i]}" = "$BRANCH" ]; then SEL_IDX=$i; break; fi
  done
  if [ "$SEL_IDX" -lt 0 ]; then
    warn "Ветка '$BRANCH' недоступна для '$CODENAME'. Есть: ${AVAIL_BR[*]}"
    SEL_IDX=$REC_IDX
    warn "Беру рекомендованную: ${AVAIL_BR[$SEL_IDX]}"
  fi
elif [ "$ASSUME_YES" -eq 1 ]; then
  SEL_IDX=$REC_IDX                              # массовый прогон → рекомендованная, молча
elif [ "$DRY_RUN" -eq 1 ]; then
  echo; print_list; echo
  SEL_IDX=$REC_IDX
else
  # ── интерактивное меню ──
  echo; print_list; echo
  printf 'Выбери вариант [1-%s] (Enter = %s): ' "${#AVAIL_BR[@]}" "$((REC_IDX+1))"
  read -r choice </dev/tty || choice=""
  [ -z "$choice" ] && choice=$((REC_IDX+1))
  case "$choice" in *[!0-9]*|'') die "Нужно число 1-${#AVAIL_BR[@]}" ;; esac
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#AVAIL_BR[@]}" ]; then
    die "Вне диапазона: 1-${#AVAIL_BR[@]}"
  fi
  SEL_IDX=$((choice-1))
fi

PKG="${AVAIL_PKG[$SEL_IDX]}"
USED_BRANCH="${AVAIL_BR[$SEL_IDX]}"
USED_V="${AVAIL_V[$SEL_IDX]}"
if [ "$USED_V" != "$PSABI" ]; then
  warn "Метапакета x64v$PSABI в ветке '$USED_BRANCH' нет — беру x64v$USED_V (совместим, ниже уровнем)"
fi

# ──────────────────────────────────────────────────────────────────────────
#  Сводка перед установкой
# ──────────────────────────────────────────────────────────────────────────
echo
printf '%s── К установке ──────────────────────────────%s\n' "$C_BOLD" "$C_RST"
printf '   ОС / релиз : %s (%s)\n' "${PRETTY_NAME:-$OS_ID}" "$CODENAME"
printf '   Репозиторий: deb.xanmod.org (суит: %s)\n' "$SUITE"
printf '   CPU уровень: x86-64-v%s\n' "$PSABI"
printf '   Ветка      : %s\n' "$USED_BRANCH"
printf '   %sПакет      : %s%s\n' "$C_GRN" "$PKG" "$C_RST"
printf '   BBR+fq     : %s\n' "$([ "$ENABLE_BBR" -eq 1 ] && echo 'включить' || echo 'не трогать')"
printf '%s─────────────────────────────────────────────%s\n' "$C_BOLD" "$C_RST"
echo

if [ "$DRY_RUN" -eq 1 ]; then
  warn "Режим --dry-run: ничего не установлено."
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────
#  9. (опц.) Полный апгрейд системы + установка ядра
# ──────────────────────────────────────────────────────────────────────────
if [ "$DO_UPGRADE" -eq 1 ]; then
  info "Полное обновление всех пакетов системы (--upgrade)…"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
  ok "Система обновлена"
fi

info "Ставлю $PKG …"
DEBIAN_FRONTEND=noninteractive apt-get install -y "$PKG"
ok "Ядро установлено"

# GRUB установщик обновляет сам, но на всякий случай
if command -v update-grub >/dev/null 2>&1; then
  update-grub >/dev/null 2>&1 || warn "update-grub вернул ошибку — проверь загрузчик вручную"
fi

# ──────────────────────────────────────────────────────────────────────────
#  10. BBR + fq (главная причина ставить XanMod на VPN-ноду)
# ──────────────────────────────────────────────────────────────────────────
if [ "$ENABLE_BBR" -eq 1 ]; then
  cat > /etc/sysctl.d/98-xanmod-bbr.conf <<'EOF'
# Включено install-xanmod.sh — BBR + fair queue
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
  # применится после ребута (модуль bbr — в новом ядре); пробуем и сейчас
  sysctl --system >/dev/null 2>&1 || true
  ok "BBR+fq прописаны (/etc/sysctl.d/98-xanmod-bbr.conf) — активируются после ребута"
fi

# ──────────────────────────────────────────────────────────────────────────
#  Готово + перезагрузка
# ──────────────────────────────────────────────────────────────────────────
echo
ok "ГОТОВО. Старое ядро осталось в GRUB как откат."
echo
printf '%sПосле перезагрузки ничего делать не нужно.%s Ядро обновляется обычным apt upgrade.\n' "$C_BOLD" "$C_RST"
printf 'Проверить можно так:  uname -r  (должно быть …-xanmod…)  и  sysctl net.ipv4.tcp_congestion_control  (bbr)\n'
printf 'Если не загрузилось — выбери старое ядро в меню GRUB → Advanced options.\n'
echo

do_reboot=0
if [ "$REBOOT" -eq 1 ]; then
  do_reboot=1                                   # --reboot: без вопроса
elif [ "$ASSUME_YES" -ne 1 ]; then
  printf 'Перезагрузить сейчас? [y/N] '
  read -r rb </dev/tty || rb=""
  case "$rb" in y|Y|yes|YES|да) do_reboot=1 ;; esac
fi
# В режиме --yes без --reboot ноду НЕ трогаем (массовый прогон — ребутишь по графику)

if [ "$do_reboot" -eq 1 ]; then
  warn "Перезагружаюсь…"
  reboot
else
  printf 'Перезагрузишь сам:  %ssudo reboot%s\n\n' "$C_BOLD" "$C_RST"
fi
