#!/bin/bash

# local env
user_account_name="leier"
user_account_groups=("adm" "wheel")
install_disk="$1"
packages_to_install=(
	"base" "base-devel" "linux-lts" "linux-lts-headers" "linux-firmware" "xfsprogs" #required
	"vim" "mousepad" # text editors
	"noto-fonts-cjk" "ttf-hack" "papirus-icon-theme" # fonts, icon themes
	"firefox" # browser of choice
	"flameshot" # screenshot utility of choice
	"bash" "bash-completion" "starship" # shell
	"cmatrix" "neofetch" "htop" # just for fun
	"curl" "git" "wget" "jq" "unzip" # must have utils
	"man-db" "man-pages" # man page support
	"lua" "luarocks" "python" "go" # programing languages
)
logfile="/tmp/arch_install.log"

function throw_error() {
	echo -e "\n\e[31mSomething went wrong!\e[0m"
	echo -e "\e[33m$1\e[0m"
	exit 1
}

function pre_checks () {
	echo -e "\033[1m:: Running pre-run checks ::\033[0m"
	# verify boot mode
	echo -n "├── UEFI bootmode: " ; [[ -e /sys/firmware/efi/efivars ]] && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	# check internet access
	echo -n "└── Internet access: " ; timeout 3 bash -c "</dev/tcp/archlinux.org/443" &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	# check amd/intel cpu mann
}

function choose_your_disk() {
	local disk_list=($(lsblk -adrnp -o NAME -I 8,259,254,179 | grep -Pv "mmcblk\dboot\d"))

	[[ -n "$install_disk" && -e "$install_disk" && -b "$install_disk" ]] && return 0

	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	lsblk -o NAME,SIZE,MOUNTPOINTS,TYPE,FSTYPE
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -

	local PS3="Select disk: "
	select disk in ${disk_list[@]} ; do
		[[ -n "$disk" && -e "$disk" && -b "$disk" ]] && break
	done

    install_disk="$disk"
    return 0
}

function partitioning() {
	local disk="$1"
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	echo -e "\033[1m:: Partitioning ::\033[0m"

	echo -n "├── wipe & unmount all: "
	umount -R /mnt &>> "$logfile"
	swapoff -a &>> "$logfile"
	wipefs -af "$disk" &>> "$logfile"
	echo -e "\e[32mOK\e[0m"
	echo -n "└── partition disk: " ; echo -e "label: gpt\n;512Mib;U;*\n;512Mib;BC13C2FF-59E6-4262-A352-B275FD6F7172\n;+;L" | sfdisk "$disk" &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }

	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	sfdisk -lq "$disk"
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -

	# registrer partitions
	local disk_partitions=($(sfdisk -lq "$disk" | grep -Po '^/dev/.*?\s'))
	local boot_partition="${disk_partitions[0]}"
	local extended_boot_partition="${disk_partitions[1]}"
	local root_partition="${disk_partitions[2]}"
	[[ ${#disk_partitions[@]} -eq 3 ]] || throw_error "Something went wrong during partitioning of disk"

	# filesystems
	echo -e "\033[1m:: Filesystems ::\033[0m"
	echo -n "├── boot partition: " ; mkfs.fat -IF 32 "$boot_partition" &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── extended boot partition: " ; mkfs.fat -IF 32 "$extended_boot_partition" &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── root partition: " ; mkfs.xfs -fL "arch_os" "$root_partition" &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── mounting root partition: " ; mount "$root_partition" /mnt && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── creating folders for mounting: " ; mkdir /mnt/{efi,boot} && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── mounting boot partition: " ; mount "$boot_partition" /mnt/efi && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── mounting extended boot partition: " ; mount "$extended_boot_partition" /mnt/boot && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── create etcetera directory: " ; (mkdir /mnt/etc ; chown root:root /mnt/etc ; chmod 0755 /mnt/etc) && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "└── make fstab: " ; (genfstab -U /mnt > /mnt/etc/fstab) && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
}

function pacstrap_and_configure_pacman() {
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	echo -e "\033[1m:: Pacstrap ::\033[0m"
	echo -n "├── check cpu type for installing ucode: "
	if [[ $(grep -P "(?<=vendor_id\s\:\s)AuthenticAMD" /proc/cpuinfo) ]] ; then
		packages_to_install+=("amd-ucode")
		echo -e "\e[31m\e[1mAMD\e[0m"
	elif [[ $(grep -P "(?<=vendor_id\s\:\s)GenuineIntel" /proc/cpuinfo) ]] ; then
		packages_to_install+=("intel-ucode")
		echo -e "\e[34m\e[1mINTEL\e[0m"
	else
		echo -e "\e[1m\e[4mN/A\e[0m"
	fi
	echo -n "├── rank mirrors: " ; reflector --country Norway,Denmark,Iceland,Finland --protocol https --sort rate --save /etc/pacman.d/mirrorlist &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── install pacman.conf for live environment: " ; (curl "https://raw.githubusercontent.com/leierr/arch-install/main/pacman.conf" > /etc/pacman.conf) &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── sync and make sure latest archlinux keyring is present: " ; pacman -Syy archlinux-keyring --noconfirm &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── running pacstrap: " ; pacstrap /mnt "${packages_to_install[@]}" &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── install pacman.conf for new system: " ; cp /etc/pacman.conf /mnt/etc/pacman.conf &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "└── rank mirrors for new system: " ; reflector --country Norway,Denmark,Iceland,Finland --protocol https --sort rate --save /mnt/etc/pacman.d/mirrorlist &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
}

function bootloader() {
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	echo -e "\033[1m:: systemd-boot ::\033[0m"
	[[ -e "/mnt/efi" && -e "/mnt/boot" ]] || throw_error "ESP or exteded boot partition does not exist or is not mounted"
	echo -n "├── install systemd-boot: " ; bootctl --esp-path=/mnt/efi --boot-path=/mnt/boot --efi-boot-option-description="Arch Linux - Autoinstall" install &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "└── install systemd-boot config file: "
	mkdir -m 755 -p /mnt/boot/loader/entries &> /dev/null
	chown root:root {/mnt/boot,/mnt/boot/loader,/mnt/boot/loader/entries} &> /dev/null
	if [[ $(grep -P "(?<=vendor_id\s\:\s)AuthenticAMD" /proc/cpuinfo) ]] ; then
		echo -e "title Arch Linux\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\ninitrd /initramfs-linux-fallback.img\ninitrd /amd-ucode.img\noptions root=\"LABEL=arch_os\" rw amd_iommu=on" > /mnt/boot/loader/entries/arch.conf && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	elif [[ $(grep -P "(?<=vendor_id\s\:\s)GenuineIntel" /proc/cpuinfo) ]] ; then
		echo -e "title Arch Linux\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\ninitrd /initramfs-linux-fallback.img\ninitrd /intel-ucode.img\noptions root=\"LABEL=arch_os\" rw intel_iommu=on" > /mnt/boot/loader/entries/arch.conf && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	else
		echo -e "title Arch Linux\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\ninitrd /initramfs-linux-fallback.img\noptions root=\"LABEL=arch_os\" rw" > /mnt/boot/loader/entries/arch.conf && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	fi
}

# function configure_users_and_groups() {}
# function configure_locale() {}
# function configure_sudoers() {}
# function configure_network() {}

clear ; setfont ter-v22n
echo "-------------------| $(TZ='Europe/Oslo' date '+%d/%m/%y %H:%M') |-------------------" >> "$logfile"
pre_checks
choose_your_disk
partitioning "$install_disk"
pacstrap_and_configure_pacman
bootloader
