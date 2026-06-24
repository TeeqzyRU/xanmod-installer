# XanMod Auto-Installer

Автоматическая установка ядра [XanMod](https://xanmod.org) на серверы **Debian** и **Ubuntu** — дедики и VPS.
*Automatic XanMod kernel installer for Debian / Ubuntu servers.*

![Bash](https://img.shields.io/badge/Bash-5%2B-4EAA25?logo=gnubash&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-A81D33?logo=debian&logoColor=white)
![Arch](https://img.shields.io/badge/Arch-x86--64-blue)
![Version](https://img.shields.io/badge/version-1.0.0-orange)
![License](https://img.shields.io/badge/License-MIT-green)

Скрипт сам определяет ОС, архитектуру, поколение CPU (`x86-64-v1…v4`), тип
виртуализации и состояние Secure Boot, показывает меню доступных веток ядра
(`main` / `lts` / `rt` / `edge`) и ставит выбранную. По умолчанию включает BBR.

---

## Возможности

- **Меню выбора ветки** — `main`, `lts`, `rt`, `edge` под конкретную машину.
- **Авто-подбор** оптимального пакета `x64vN` по набору инструкций процессора.
- **Защита от неподходящего окружения** — ARM, 32-bit, контейнеры (OpenVZ/LXC),
  включённый Secure Boot отсекаются с понятным сообщением.
- **apt-pin** — из репозитория XanMod берутся только ядра; системные пакеты
  остаются из дистрибутива.
- **BBR + fq** включаются из коробки (отключается флагом `--no-bbr`).
- **Безопасный откат** — старое ядро остаётся в меню GRUB.
- **Ручной и массовый режимы** — интерактивное меню или `--yes --reboot` для парка.

> **Какие ветки доступны:** репозиторий XanMod работает по кодовому имени релиза.
> На **Debian 13** (trixie) и **Ubuntu** доступны `main` / `lts` / `rt`.
> На **Debian 12** (bookworm) XanMod публикует только `lts`.

---

## Установка

Команды под `root` (на большинстве VPS вход сразу root). Если ты не root — добавь `sudo`.

```bash
# с меню выбора ветки (запускать БЕЗ --yes)
curl -fsSL https://raw.githubusercontent.com/TeeqzyRU/xanmod-installer/main/install-xanmod.sh | bash

# массово на ноду: рекомендованная ветка + сразу перезагрузка
curl -fsSL https://raw.githubusercontent.com/TeeqzyRU/xanmod-installer/main/install-xanmod.sh | bash -s -- --yes --reboot
```

При запуске без флагов выводится меню:

```
Доступные ядра XanMod для trixie (CPU: x86-64-v3):
  1) main  linux-xanmod-x64v3        стабильная, свежее ядро — обычный выбор   ← рекомендую
  2) lts   linux-xanmod-lts-x64v3    LTS — макс. стабильность, для прода/DKMS
  3) rt    linux-xanmod-rt-x64v3     real-time (PREEMPT_RT) — низкие задержки
Выбери вариант [1-3] (Enter = 1):
```

---

## Использование

| Флаг | Назначение |
|---|---|
| *(без флагов)* | меню выбора ветки, затем вопрос про перезагрузку |
| `--list` | показать доступные ядра под эту ОС и выйти |
| `--branch main\|lts\|rt\|edge` | поставить конкретную ветку без меню |
| `-y`, `--yes` | без вопросов, рекомендованная ветка (для массового деплоя), без ребута |
| `--reboot` | перезагрузить в конце без вопроса (для `--yes`) |
| `--upgrade` | сделать полный `apt upgrade` перед установкой ядра |
| `--no-bbr` | не трогать sysctl (по умолчанию включает `BBR + fq`) |
| `--dry-run` | показать, что будет сделано, ничего не устанавливая |
| `--force-secureboot` | продолжить при включённом Secure Boot (на свой риск) |
| `-V`, `--version` | показать версию |
| `-h`, `--help` | справка |

---

## Как работает

1. Проверяет ОС, архитектуру, виртуализацию, Secure Boot и поколение CPU.
2. Подключает репозиторий XanMod (ключ + apt-pin) и обновляет его индекс.
3. Показывает меню веток → выбор номером (или сразу ставит при `--branch` / `--yes`).
4. Устанавливает ядро и прописывает `BBR + fq`.
5. Предлагает перезагрузиться сейчас или позже.

После перезагрузки делать ничего не нужно — ядро дальше обновляется обычным `apt upgrade`.

---

## Что проверяется перед установкой

| Проверка | Поведение |
|---|---|
| ОС | только Debian / Ubuntu (apt), иначе выход |
| Архитектура | только `x86_64`; ARM и 32-bit отклоняются |
| Виртуализация | контейнеры (OpenVZ / LXC / Docker) отклоняются — ядро общее с хостом |
| Secure Boot | если включён — выход (ядро XanMod не подписано ключом Microsoft) |
| Поколение CPU | подбирается максимальный доступный `x64vN` (≤ возможностей CPU) |

---

## После установки

```bash
uname -r                                # содержит "xanmod"
sysctl net.ipv4.tcp_congestion_control  # bbr
```

Если новое ядро не загрузилось — в меню GRUB → **Advanced options** выбери предыдущее ядро.

---

## Совместимость

- **Debian** 12 (bookworm, только `lts`), 13 (trixie) и новее
- **Ubuntu** 24.04 (noble) и другие поддерживаемые релизы
- Архитектура **x86-64** (amd64); ARM не поддерживается (XanMod собирается только под amd64)
- Только полноценное ядро: дедики, KVM, Xen-HVM, VMware. **Не** контейнеры.

---

## Лицензия

[MIT](LICENSE). XanMod распространяется под GPLv2 — см. [xanmod.org](https://xanmod.org).
