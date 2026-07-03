#!/usr/bin/env bash
#
# fedora44-post-install.sh
# Skrip otomasi interaktif untuk Fedora 44 Post Install Guide
# Berdasarkan: Fedora 44 Post Install Guide (README.md)
#
# Cara pakai:
#   chmod +x fedora44-post-install.sh
#   ./fedora44-post-install.sh
#
# CATATAN: Jangan jalankan skrip ini sebagai root langsung (jangan sudo ./script.sh).
# Skrip akan memanggil sudo sendiri hanya saat dibutuhkan.

set -uo pipefail

# ------------------------------------------------------------------
# Konfigurasi umum
# ------------------------------------------------------------------
LOG_FILE="$HOME/fedora44-post-install.log"
SCRIPT_NAME="Fedora 44 Post Install Guide - Automation"

C_RESET="\e[0m"
C_BOLD="\e[1m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_RED="\e[31m"
C_CYAN="\e[36m"
C_BLUE="\e[34m"

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') | $*" >> "$LOG_FILE"
}

msg() {
    echo -e "${C_CYAN}${C_BOLD}[*]${C_RESET} $*"
}

ok() {
    echo -e "${C_GREEN}${C_BOLD}[OK]${C_RESET} $*"
}

warn() {
    echo -e "${C_YELLOW}${C_BOLD}[!]${C_RESET} $*"
}

err() {
    echo -e "${C_RED}${C_BOLD}[X]${C_RESET} $*"
}

pause() {
    read -rp "$(echo -e "${C_BLUE}Tekan ENTER untuk lanjut...${C_RESET}")" _
}

confirm() {
    # confirm "Pertanyaan?" -> return 0 kalau ya
    local prompt="$1"
    local ans
    read -rp "$(echo -e "${C_YELLOW}${prompt} [y/N]: ${C_RESET}")" ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

# Jalankan perintah, log, dan handle error tanpa mematikan skrip
run() {
    local desc="$1"
    shift
    msg "Menjalankan: $desc"
    log "CMD: $*"
    if "$@" >>"$LOG_FILE" 2>&1; then
        ok "$desc"
        return 0
    else
        err "Gagal: $desc (lihat $LOG_FILE untuk detail)"
        return 1
    fi
}

# Sama seperti run(), tapi untuk perintah shell string kompleks (pipe, subshell, dll)
run_sh() {
    local desc="$1"
    local cmd="$2"
    msg "Menjalankan: $desc"
    log "SH: $cmd"
    if bash -c "$cmd" >>"$LOG_FILE" 2>&1; then
        ok "$desc"
        return 0
    else
        err "Gagal: $desc (lihat $LOG_FILE untuk detail)"
        return 1
    fi
}

require_not_root() {
    if [[ "$EUID" -eq 0 ]]; then
        err "Jangan jalankan skrip ini langsung sebagai root/dengan sudo."
        echo "Cukup jalankan: ./$(basename "$0")"
        echo "Skrip akan minta password sudo otomatis saat diperlukan."
        exit 1
    fi
}

require_fedora() {
    if [[ ! -f /etc/fedora-release ]]; then
        warn "Sistem ini sepertinya bukan Fedora. Skrip ini didesain khusus untuk Fedora 44."
        confirm "Tetap lanjutkan?" || exit 1
    fi
}

sudo_keepalive() {
    # Minta password sudo di awal supaya tidak nanya-nanya terus di tengah proses
    msg "Beberapa langkah butuh akses sudo. Silakan masukkan password kamu:"
    sudo -v
    # Perpanjang otomatis sampai skrip selesai
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
}

cleanup() {
    [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
}
trap cleanup EXIT

banner() {
    clear
    echo -e "${C_BOLD}${C_CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║        Fedora 44 Post Install Guide — Skrip Otomasi           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${C_RESET}"
    echo "Log lengkap disimpan di: $LOG_FILE"
    echo
}

# ------------------------------------------------------------------
# 1. RPM Fusion
# ------------------------------------------------------------------
step_rpmfusion() {
    banner
    echo -e "${C_BOLD}== RPM Fusion (Free & Non-Free) ==${C_RESET}"
    echo "Mengaktifkan repo pihak ketiga untuk software seperti Steam, Discord, codec multimedia, dll."
    confirm "Aktifkan RPM Fusion sekarang?" || return
    run "Install RPM Fusion free & nonfree" \
        sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
    run "Upgrade grup core (appstream metadata)" sudo dnf group upgrade -y core
    run "Install grup core via dnf4" sudo dnf4 group install -y core
    pause
}

# ------------------------------------------------------------------
# 2. System Update
# ------------------------------------------------------------------
step_update() {
    banner
    echo -e "${C_BOLD}== Update Sistem ==${C_RESET}"
    confirm "Update semua paket sistem sekarang? (disarankan)" || return
    run "dnf update" sudo dnf -y update
    if confirm "Reboot sekarang untuk menerapkan update? (bisa dilewati dan reboot manual nanti)"; then
        REBOOT_REQUESTED=1
    fi
}

# ------------------------------------------------------------------
# 3. Firmware Update (fwupd/LVFS)
# ------------------------------------------------------------------
step_firmware() {
    banner
    echo -e "${C_BOLD}== Firmware Update (LVFS) ==${C_RESET}"
    echo "Mengecek update firmware perangkat (jika didukung)."
    confirm "Cek & update firmware sekarang?" || return
    run "Refresh metadata firmware" sudo fwupdmgr refresh --force
    msg "Daftar device firmware:"
    sudo fwupdmgr get-devices | tee -a "$LOG_FILE"
    msg "Daftar update yang tersedia:"
    sudo fwupdmgr get-updates | tee -a "$LOG_FILE"
    if confirm "Install update firmware yang tersedia?"; then
        run "Update firmware" sudo fwupdmgr update
    fi
    pause
}

# ------------------------------------------------------------------
# 4. Flatpak (Flathub full repo)
# ------------------------------------------------------------------
step_flatpak() {
    banner
    echo -e "${C_BOLD}== Flatpak / Flathub ==${C_RESET}"
    confirm "Pastikan Flathub (semua flatpak, termasuk non-free) aktif?" || return
    run "Tambah remote Flathub" flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    pause
}

# ------------------------------------------------------------------
# 5. AppImage support
# ------------------------------------------------------------------
step_appimage() {
    banner
    echo -e "${C_BOLD}== Dukungan AppImage ==${C_RESET}"
    confirm "Install FUSE untuk AppImage?" || return
    run "Install fuse-libs" sudo dnf install -y fuse-libs
    if confirm "Install Gearlever (manajer AppImage via Flatpak)?"; then
        run "Install Gearlever" flatpak install -y it.mijorus.gearlever
    fi
    pause
}

# ------------------------------------------------------------------
# 6. NVIDIA Drivers
# ------------------------------------------------------------------
step_nvidia() {
    banner
    echo -e "${C_BOLD}== Driver NVIDIA ==${C_RESET}"

    if ! lspci | grep -qi nvidia; then
        warn "Tidak terdeteksi GPU NVIDIA di sistem ini (via lspci)."
        confirm "Tetap lanjutkan proses instalasi driver NVIDIA?" || return
    fi

    confirm "Lanjutkan instalasi driver NVIDIA?" || return

    run "Update sistem & kernel" sudo dnf -y update
    warn "Kalau kernel baru saja diupdate, sebaiknya reboot dulu sebelum lanjut, lalu jalankan opsi ini lagi."
    confirm "Kernel sudah versi terbaru & sudah reboot jika perlu?" || return

    local sb_state
    sb_state=$(mokutil --sb-state 2>/dev/null || echo "unknown")
    echo "Status Secure Boot: $sb_state"

    if echo "$sb_state" | grep -qi "enabled"; then
        echo -e "${C_YELLOW}Secure Boot AKTIF. Perlu proses enroll MOK key.${C_RESET}"
        confirm "Lanjutkan setup NVIDIA dengan Secure Boot (jalur A)?" || return

        run "Install tools MOK" sudo dnf install -y kmodtool akmods mokutil openssl
        msg "Generate signing key..."
        if ! sudo kmodgenca -a >>"$LOG_FILE" 2>&1; then
            warn "Kemungkinan key sudah ada. Mencoba ulang dengan --force..."
            run "Generate key (force)" sudo kmodgenca -a --force
        fi
        echo
        echo -e "${C_BOLD}${C_YELLOW}PENTING:${C_RESET} Sekarang akan diminta membuat password MOK sementara."
        echo "Ingat password ini (mis. 1234), akan dipakai saat reboot di layar biru MOK."
        pause
        sudo mokutil --import /etc/pki/akmods/certs/public_key.der
        echo
        warn "Setelah ini kamu HARUS reboot manual, lalu di layar biru pilih:"
        echo "  Enroll MOK -> Continue -> Yes -> masukkan password yang tadi dibuat"
        echo "Setelah reboot & enroll selesai, jalankan skrip ini lagi dan pilih 'Install paket driver NVIDIA (lanjutan)' di menu NVIDIA."
        if confirm "Reboot sekarang?"; then
            log "Reboot untuk MOK enroll"
            sudo systemctl reboot
        fi
        return
    else
        echo -e "${C_GREEN}Secure Boot tidak aktif. Bisa langsung install driver.${C_RESET}"
    fi

    nvidia_install_packages
}

nvidia_install_packages() {
    confirm "Install akmod-nvidia sekarang?" || return
    run "Install akmod-nvidia" sudo dnf install -y akmod-nvidia
    if confirm "Install juga dukungan CUDA (untuk Blender/Davinci Resolve/dll)?"; then
        run "Install xorg-x11-drv-nvidia-cuda" sudo dnf install -y xorg-x11-drv-nvidia-cuda
    fi
    warn "Kernel module butuh waktu ±5 menit untuk build. Jangan reboot dulu sebelum ini selesai."
    if confirm "Tunggu & cek status build sekarang (bisa beberapa menit)?"; then
        local tries=0
        until modinfo -F version nvidia >/dev/null 2>&1; do
            tries=$((tries+1))
            if [[ $tries -gt 30 ]]; then
                warn "Masih belum selesai setelah beberapa menit. Cek manual nanti dengan: modinfo -F version nvidia"
                break
            fi
            echo -ne "\rMenunggu kmod ter-build... (${tries}0 detik)"
            sleep 10
        done
        echo
        if modinfo -F version nvidia >/dev/null 2>&1; then
            ok "Driver NVIDIA versi $(modinfo -F version nvidia) berhasil dibuild."
            confirm "Reboot sekarang untuk mengaktifkan driver?" && sudo systemctl reboot
        fi
    else
        msg "Cek manual nanti dengan: modinfo -F version nvidia"
    fi
    pause
}

# ------------------------------------------------------------------
# 7. Media Codecs
# ------------------------------------------------------------------
step_codecs() {
    banner
    echo -e "${C_BOLD}== Media Codecs ==${C_RESET}"
    echo "Perlu RPM Fusion sudah aktif (jalankan step 1 dulu kalau belum)."
    confirm "Install paket multimedia lengkap?" || return
    run "Install grup multimedia" sudo dnf4 group install -y multimedia
    run "Swap ke FFmpeg penuh" sudo dnf swap -y 'ffmpeg-free' 'ffmpeg' --allowerasing
    run "Update grup multimedia (gstreamer dll)" sudo dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
    run "Install grup sound-and-video" sudo dnf group install -y sound-and-video
    pause
}

# ------------------------------------------------------------------
# 8. H/W Video Acceleration
# ------------------------------------------------------------------
step_hwvideo() {
    banner
    echo -e "${C_BOLD}== Hardware Video Acceleration (VA-API) ==${C_RESET}"
    confirm "Install paket dasar VA-API?" || return
    run "Install ffmpeg-libs, libva, libva-utils" sudo dnf install -y ffmpeg-libs libva libva-utils

    local gpu_vendor="unknown"
    if lspci | grep -qi 'VGA.*Intel\|3D.*Intel'; then
        gpu_vendor="intel"
    fi
    if lspci | grep -qi 'VGA.*AMD\|3D.*AMD\|VGA.*ATI'; then
        gpu_vendor="amd"
    fi

    echo "GPU terdeteksi: $gpu_vendor (kalau salah/hybrid, bisa pilih manual di bawah)"

    local choice
    echo "Pilih driver VA-API yang mau diinstall:"
    select choice in "Intel" "AMD" "Skip"; do
        case $choice in
            Intel)
                run "Swap ke intel-media-driver" sudo dnf swap -y libva-intel-media-driver intel-media-driver --allowerasing
                run "Install libva-intel-driver (legacy)" sudo dnf install -y libva-intel-driver
                break
                ;;
            AMD)
                run "Install mesa-va-drivers-freeworld" sudo dnf install -y mesa-va-drivers-freeworld
                run "Install mesa-va-drivers-freeworld.i686" sudo dnf install -y mesa-va-drivers-freeworld.i686
                break
                ;;
            Skip|*)
                break
                ;;
        esac
    done
    pause
}

# ------------------------------------------------------------------
# 9. OpenH264 untuk Firefox
# ------------------------------------------------------------------
step_openh264() {
    banner
    echo -e "${C_BOLD}== OpenH264 untuk Firefox ==${C_RESET}"
    confirm "Install OpenH264?" || return
    run "Install openh264 & plugin gstreamer/mozilla" sudo dnf install -y openh264 gstreamer1-plugin-openh264 mozilla-openh264
    run "Enable repo fedora-cisco-openh264" sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
    warn "Terakhir, buka Firefox -> about:addons -> Plugins, lalu aktifkan 'OpenH264 Video Codec' secara manual."
    pause
}

# ------------------------------------------------------------------
# 10. Hostname
# ------------------------------------------------------------------
step_hostname() {
    banner
    echo -e "${C_BOLD}== Set Hostname ==${C_RESET}"
    echo "Hostname sekarang: $(hostnamectl --static 2>/dev/null || hostname)"
    if confirm "Ganti hostname?"; then
        read -rp "Masukkan hostname baru: " newhost
        if [[ -n "$newhost" ]]; then
            run "Set hostname ke $newhost" sudo hostnamectl set-hostname "$newhost"
        else
            warn "Hostname kosong, dilewati."
        fi
    fi
    pause
}

# ------------------------------------------------------------------
# 11. Firefox default start page
# ------------------------------------------------------------------
step_firefox_startpage() {
    banner
    echo -e "${C_BOLD}== Firefox Default Start Page ==${C_RESET}"
    echo "Menghapus override start page Fedora agar Firefox pakai halaman start default-nya sendiri."
    confirm "Lanjutkan?" || return
    run "Hapus firefox-redhat-default-prefs.js" sudo rm -f /usr/lib64/firefox/browser/defaults/preferences/firefox-redhat-default-prefs.js
    pause
}

# ------------------------------------------------------------------
# 12. Custom DNS (DNS over TLS)
# ------------------------------------------------------------------
step_dns() {
    banner
    echo -e "${C_BOLD}== Custom DNS Servers (DNS over TLS - Cloudflare) ==${C_RESET}"
    echo "Akan membuat file konfigurasi systemd-resolved untuk DoT via Cloudflare."
    confirm "Setup custom DNS sekarang?" || return

    sudo mkdir -p /etc/systemd/resolved.conf.d
    local conf="/etc/systemd/resolved.conf.d/99-dns-over-tls.conf"
    local content
    content=$(cat <<'EOF'
[Resolve]
DNS=1.1.1.2#security.cloudflare-dns.com 1.0.0.2#security.cloudflare-dns.com 2606:4700:4700::1112#security.cloudflare-dns.com 2606:4700:4700::1002#security.cloudflare-dns.com
DNSOverTLS=yes
Domains=~.
EOF
)
    if echo "$content" | sudo tee "$conf" >/dev/null; then
        ok "File konfigurasi dibuat: $conf"
        run "Restart systemd-resolved" sudo systemctl restart systemd-resolved
    else
        err "Gagal membuat file konfigurasi DNS."
    fi
    pause
}

# ------------------------------------------------------------------
# 13. UTC time (dual boot fix)
# ------------------------------------------------------------------
step_utc() {
    banner
    echo -e "${C_BOLD}== Set RTC ke UTC (fix jam dual-boot Windows) ==${C_RESET}"
    confirm "Set local RTC ke UTC?" || return
    run "Set local-rtc ke 0 (UTC)" sudo timedatectl set-local-rtc '0'
    pause
}

# ------------------------------------------------------------------
# 14. Optimizations
# ------------------------------------------------------------------
step_optimizations() {
    banner
    echo -e "${C_BOLD}== Optimasi Boot & Startup ==${C_RESET}"

    if confirm "Disable NetworkManager-wait-online.service (percepat boot ~15-20s)?"; then
        run "Disable NetworkManager-wait-online.service" sudo systemctl disable NetworkManager-wait-online.service
    fi

    if confirm "Disable GNOME Software dari autostart & search provider (hemat RAM)?"; then
        mkdir -p ~/.config/autostart
        if [[ -f /usr/share/applications/org.gnome.Software.desktop ]]; then
            cp /usr/share/applications/org.gnome.Software.desktop ~/.config/autostart/ 2>>"$LOG_FILE"
            echo "X-GNOME-Autostart-enabled=false" >> ~/.config/autostart/org.gnome.Software.desktop
            ok "GNOME Software autostart dinonaktifkan."
        else
            warn "File org.gnome.Software.desktop tidak ditemukan, dilewati."
        fi
        if command -v dconf >/dev/null 2>&1; then
            run "Disable GNOME Software sebagai search provider" dconf write /org/gnome/desktop/search-providers/disabled "['org.gnome.Software.desktop']"
        fi
    fi
    pause
}

# ------------------------------------------------------------------
# 15. GNOME Extensions (optional)
# ------------------------------------------------------------------
step_gnome_extensions() {
    banner
    echo -e "${C_BOLD}== GNOME Extensions (Opsional) ==${C_RESET}"
    warn "Hanya untuk GNOME stock Fedora Workstation. Jangan install kalau pakai spin lain (KDE, dll)."
    confirm "Lanjutkan?" || return

    if confirm "Install Pop Shell (tiling window manager)?"; then
        run "Install pop-shell & xprop" sudo dnf install -y gnome-shell-extension-pop-shell xprop
    fi

    if confirm "Install dependensi GSConnect (nautilus-python + firewall rule)?"; then
        run "Install nautilus-python" sudo dnf install -y nautilus-python
        run "Buka firewall untuk kdeconnect" sudo firewall-cmd --permanent --zone=public --add-service=kdeconnect
        run "Reload firewall" sudo firewall-cmd --reload
        msg "Install ekstensi GSConnect-nya sendiri manual lewat extensions.gnome.org."
    fi

    echo
    echo "Ekstensi lain di bawah ini perlu diinstall manual lewat https://extensions.gnome.org/ atau Extension Manager:"
    cat <<'EOF'
  - Gesture Improvements
  - Quick Settings Tweaker
  - User Themes
  - Compiz Windows Effect
  - Just Perfection
  - Rounded Window Corners
  - Dash to Dock
  - Blur My Shell
  - Bluetooth Quick Connect
  - App Indicator Support
  - Clipboard Indicator
  - Legacy (GTK3) Theme Scheme Auto Switcher
  - Caffeine
  - Vitals
  - Wireless HID
  - Logo Menu
  - Space Bar (https://github.com/christopher-l/space-bar)
EOF
    if confirm "Install 'Extension Manager' (buat install ekstensi GNOME lebih gampang lewat GUI)?"; then
        run "Install Extension Manager via Flatpak" flatpak install -y flathub com.mattjakeman.ExtensionManager
    fi
    pause
}

# ------------------------------------------------------------------
# 16. Optional Apps
# ------------------------------------------------------------------
step_apps() {
    banner
    echo -e "${C_BOLD}== Aplikasi Tambahan (Opsional) ==${C_RESET}"

    if confirm "Install dukungan RAR/7z (unzip, p7zip, unrar)?"; then
        run "Install compression tools" sudo dnf install -y unzip p7zip p7zip-plugins unrar
    fi

    # flatpak app id yang paling mendekati nama app di README
    declare -A APP_MAP=(
        ["7zip"]="org.gnome.zip"
        ["Amberol"]="io.bassi.Amberol"
        ["Blanket"]="com.rafaelmardojai.Blanket"
        ["Builder"]="org.gnome.Builder"
        ["Brave"]="com.brave.Browser"
        ["Blender"]="org.blender.Blender"
        ["Discord"]="com.discordapp.Discord"
        ["Drawing"]="com.github.maoschanz.drawing"
        ["Deja Dup Backups"]="org.gnome.DejaDup"
        ["Endeavour"]="io.github.mrvladus.List"
        ["Easyeffects"]="com.github.wwmm.easyeffects"
        ["Extension Manager"]="com.mattjakeman.ExtensionManager"
        ["Flatseal"]="com.github.tchx84.Flatseal"
        ["Foliate"]="com.github.johnfactotum.Foliate"
        ["GIMP"]="org.gimp.GIMP"
        ["Gnome Tweaks"]="org.gnome.tweaks"
        ["Gradience"]="com.github.GradienceTeam.Gradience"
        ["Handbrake"]="fr.handbrake.ghb"
        ["Iotas"]="com.mardojai.Iotas"
        ["Joplin"]="net.cozic.joplin_desktop"
        ["Khronos"]="dev.emmett.Khronos"
        ["Krita"]="org.kde.krita"
        ["Logseq"]="com.logseq.Logseq"
        ["Onlyoffice"]="org.onlyoffice.desktopeditors"
        ["Overskride"]="io.github.kaii_lb.Overskride"
        ["Parabolic"]="org.nickvision.tubeconverter"
        ["Pcloud"]="com.pcloud.drive"
        ["PDF Arranger"]="com.github.jeromerobert.pdfarranger"
        ["Planify"]="io.github.alainm23.planify"
        ["Pika backup"]="org.gnome.World.PikaBackup"
        ["Snapshot"]="org.gnome.Snapshot"
        ["Solanum"]="org.gnome.Solanum"
        ["Sound Recorder"]="org.gnome.SoundRecorder"
        ["Tangram"]="re.sonny.Tangram"
        ["Transmission"]="com.transmissionbt.Transmission"
        ["Ulauncher"]="io.ulauncher.Ulauncher"
        ["Upscaler"]="io.gitlab.theevilskeleton.Upscaler"
        ["Video Trimmer"]="org.gnome.gitlab.YaLTeR.VideoTrimmer"
        ["VS Codium"]="com.vscodium.codium"
    )

    echo "Pilih aplikasi yang mau diinstall via Flatpak (bisa pilih beberapa, pisahkan angka dengan spasi, atau 'all' untuk semua, 'skip' untuk lewati):"
    echo
    local i=1
    local names=()
    for name in "${!APP_MAP[@]}"; do
        names+=("$name")
    done
    IFS=$'\n' names=($(sort <<<"${names[*]}")); unset IFS
    for name in "${names[@]}"; do
        printf "  %2d) %s\n" "$i" "$name"
        i=$((i+1))
    done
    echo
    read -rp "Pilihan: " selection

    if [[ "$selection" == "skip" || -z "$selection" ]]; then
        msg "Dilewati."
    else
        local to_install=()
        if [[ "$selection" == "all" ]]; then
            to_install=("${names[@]}")
        else
            for num in $selection; do
                idx=$((num-1))
                if [[ $idx -ge 0 && $idx -lt ${#names[@]} ]]; then
                    to_install+=("${names[$idx]}")
                fi
            done
        fi
        for app in "${to_install[@]}"; do
            appid="${APP_MAP[$app]}"
            run "Install $app ($appid)" flatpak install -y flathub "$appid"
        done
    fi

    echo
    warn "Catatan: beberapa app id di atas adalah perkiraan terbaik (Flathub bisa berubah)."
    warn "Kalau ada yang gagal/app id salah, cari manual di https://flathub.org lalu install dengan:"
    echo "  flatpak install flathub <app.id.di.sini>"

    if confirm "Install yt-dlp dan lm_sensors via dnf juga?"; then
        run "Install yt-dlp & lm_sensors" sudo dnf install -y yt-dlp lm_sensors
    fi
    pause
}

# ------------------------------------------------------------------
# 17. Theming
# ------------------------------------------------------------------
step_theming() {
    banner
    echo -e "${C_BOLD}== Theming (Opsional) ==${C_RESET}"
    warn "Bagian ini hanya link referensi (GTK theme, ikon, wallpaper, dll) — tidak diinstall otomatis"
    warn "karena butuh clone/build manual dari GitHub masing-masing. Skrip akan bukakan izin flatpak theming saja."

    if confirm "Izinkan Flatpak akses folder ~/.themes (supaya app Flatpak bisa pakai GTK theme custom)?"; then
        run "Override flatpak filesystem ~/.themes" sudo flatpak override --filesystem="$HOME/.themes"
    fi

    echo
    echo "Referensi tema (install manual sesuai selera):"
    cat <<'EOF'
  GTK Themes:
    - https://github.com/lassekongo83/adw-gtk3
    - https://github.com/vinceliuice/Colloid-gtk-theme
    - https://github.com/EliverLara/Nordic
    - https://github.com/vinceliuice/Orchis-theme
    - https://github.com/vinceliuice/Graphite-gtk-theme
  Icon Packs:
    - https://github.com/vinceliuice/Tela-icon-theme
    - https://github.com/vinceliuice/Colloid-gtk-theme/tree/main/icon-theme
  Wallpaper:
    - https://github.com/manishprivet/dynamic-gnome-wallpapers
  Grub Theme:
    - https://github.com/vinceliuice/grub2-themes
EOF

    if confirm "Install Firefox GNOME theme (via curl | bash dari repo resmi rafaelmardojai)?"; then
        warn "Ini akan menjalankan install script pihak ketiga (curl | bash)."
        confirm "Kamu paham risikonya dan tetap mau lanjut?" && \
            run_sh "Install Firefox GNOME theme" \
            "curl -s -o- https://raw.githubusercontent.com/rafaelmardojai/firefox-gnome-theme/master/scripts/install-by-curl.sh | bash"
    fi

    if confirm "Install Starship prompt (terminal theme)?"; then
        run_sh "Install Starship" "curl -sS https://starship.rs/install.sh | sh -s -- -y"
        echo
        msg "Jangan lupa tambahkan baris berikut ke ~/.bashrc atau ~/.zshrc kamu:"
        echo '  eval "$(starship init bash)"   # kalau pakai bash'
        echo '  eval "$(starship init zsh)"    # kalau pakai zsh'
    fi
    pause
}

# ------------------------------------------------------------------
# Menu utama
# ------------------------------------------------------------------
main_menu() {
    while true; do
        banner
        cat <<EOF
Pilih langkah yang mau dijalankan (bisa diulang, urutan bebas,
tapi disarankan urut dari atas ke bawah untuk pemula):

  1)  RPM Fusion (repo pihak ketiga)
  2)  Update sistem
  3)  Firmware update (LVFS)
  4)  Flatpak / Flathub
  5)  Dukungan AppImage
  6)  Driver NVIDIA
  7)  Media codecs
  8)  Hardware video acceleration
  9)  OpenH264 untuk Firefox
  10) Set hostname
  11) Firefox default start page
  12) Custom DNS (DNS over TLS)
  13) Set RTC ke UTC (dual boot fix)
  14) Optimasi boot/startup
  15) GNOME Extensions (opsional)
  16) Install aplikasi tambahan (opsional)
  17) Theming (opsional)

  A)  Jalankan SEMUA langkah wajib berurutan (1,2,3,4,5,7,8,9,10,13,14)
      (NVIDIA, extensions, apps, theming tetap ditanya terpisah karena opsional/butuh input)
  L)  Lihat log
  Q)  Keluar
EOF
        echo
        read -rp "Pilihan kamu: " opt
        case "$opt" in
            1) step_rpmfusion ;;
            2) step_update ;;
            3) step_firmware ;;
            4) step_flatpak ;;
            5) step_appimage ;;
            6) step_nvidia ;;
            7) step_codecs ;;
            8) step_hwvideo ;;
            9) step_openh264 ;;
            10) step_hostname ;;
            11) step_firefox_startpage ;;
            12) step_dns ;;
            13) step_utc ;;
            14) step_optimizations ;;
            15) step_gnome_extensions ;;
            16) step_apps ;;
            17) step_theming ;;
            [Aa])
                step_rpmfusion
                step_update
                step_firmware
                step_flatpak
                step_appimage
                step_codecs
                step_hwvideo
                step_openh264
                step_hostname
                step_utc
                step_optimizations
                echo
                ok "Langkah wajib selesai. NVIDIA, GNOME Extensions, Apps, dan Theming"
                echo "bisa dijalankan terpisah dari menu (opsi 6, 15, 16, 17) karena butuh input kamu."
                pause
                ;;
            [Ll])
                banner
                if [[ -f "$LOG_FILE" ]]; then
                    tail -n 60 "$LOG_FILE"
                else
                    echo "Belum ada log."
                fi
                pause
                ;;
            [Qq])
                echo
                if [[ "${REBOOT_REQUESTED:-0}" -eq 1 ]]; then
                    if confirm "Ada permintaan reboot tertunda. Reboot sekarang?"; then
                        sudo systemctl reboot
                    fi
                fi
                msg "Selesai. Log lengkap ada di: $LOG_FILE"
                exit 0
                ;;
            *)
                warn "Pilihan tidak valid."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------
require_not_root
require_fedora
: > "$LOG_FILE"
log "=== $SCRIPT_NAME dimulai ==="
sudo_keepalive
REBOOT_REQUESTED=0
main_menu
