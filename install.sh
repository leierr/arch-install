#!/bin/bash

# local env
user_account_name="leier"
user_account_groups=("adm" "wheel")
install_disk=""
packages_to_install=(
	"base" "base-devel" "linux-lts" "linux-lts-headers" "linux-firmware" "xfsprogs" #required
	"vim" "mousepad" # text editors
	"noto-fonts-cjk" "ttf-hack" "papirus-icon-theme" # fonts, icon themes
	"firefox" # browser of choice
	"flameshot" # screenshot utility of choice
	"bash" "bash-completion" "zsh" # shell
	"cmatrix" "neofetch" "htop" # just for fun
	"curl" "git" "wget" "jq" "unzip" # must have utils
	"man-db" "man-pages" # man page support
	"lua" "luarocks" "python" "go" # programing languages
)

function throw_error() {
	echo -e "\n\e[31mSomething went wrong!\e[0m"
	echo -e "\e[33m$1\e[0m"
	exit 1
}

function pre_checks () {
	echo -e "\033[1m:: Running pre-run checks ::\033[0m"
	# verify boot mode
	echo -n "-> UEFI bootmode: " ; [[ -e /sys/firmware/efi/efivars ]] && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	# check internet access
	echo -n "-> Internet access: " ; timeout 3 bash -c "</dev/tcp/archlinux.org/443" 2>/dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	# check amd/intel cpu mann
}

function choose_your_disk() {
	local disks_list=($(lsblk -adrnp -o NAME -I 8,259,254,179 | grep -Pv "mmcblk\dboot\d"))

	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	lsblk -o NAME,SIZE,MOUNTPOINTS,TYPE,FSTYPE
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -

	local PS3="Select disk: "
	select disk in ${disks_list[@]} ; do
		install_disk=$disk
		[[ -n "$disk" ]] && break
	done

	[[ -n "$install_disk" && -e "$install_disk" ]] && return 0 || throw_error "Disk not found"
}

function partitioning() {
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	echo -e "\033[1m:: Partitioning ::\033[0m"

	echo -n " -> wipe & unmount all: "
	umount -R /mnt &> /dev/null
	swapoff -a &> /dev/null
	wipefs -af $1 &> /dev/null
	echo -e "\e[32mOK\e[0m"

	echo -n " -> partition disk: "
	echo -e "label: gpt\n;512Mib;U;*\n;512Mib;BC13C2FF-59E6-4262-A352-B275FD6F7172\n;+;L" | sfdisk $1 &> /dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }

	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	sfdisk -lq $1
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -

	# registrer partitions
	local disk_partitions=($(sfdisk -lq $1 | grep -Po '^/dev/.*?\s'))
	local boot_partition="${disk_partitions[0]}"
	local extended_boot_partition="${disk_partitions[1]}"
	local root_partition="${disk_partitions[2]}"
	[[ ${#disk_partitions[@]} -eq 3 ]] || throw_error "Something went wrong during partitioning of disk"

	# filesystems
	echo -e "\033[1m:: Filesystems ::\033[0m"
	echo -n " -> boot partition: " ; mkfs.fat -IF 32 $boot_partition &> /dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n " -> extended boot partition: " ; mkfs.fat -IF 32 $extended_boot_partition &> /dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n " -> root partition: " ; mkfs.xfs -f $root_partition &> /dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n " -> mounting root partition: " ; mount $root_partition /mnt && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n " -> creating folders for mounting: " ; mkdir /mnt/{efi,boot} && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n " -> mounting boot partition: " ; mount $boot_partition /mnt/efi && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n " -> mounting extended boot partition: " ; mount $extended_boot_partition /mnt/boot && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n " -> create etcetera directory: " ; (mkdir /mnt/etc ; chown root:root /mnt/etc ; chmod 0755 /mnt/etc) && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n " -> make fstab: " ; (genfstab -U /mnt > /mnt/etc/fstab) && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
}

function pacstrap_and_configure_pacman() {
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	echo -e "\033[1m:: Pacstrap ::\033[0m"
	echo -n " -> rank mirrors: " ; reflector --country Norway,Denmark,Iceland,Finland --protocol https --sort rate --save /etc/pacman.d/mirrorlist &> /dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n " -> install pacman.conf for live environment: " ; (curl "https://raw.githubusercontent.com/leierr/arch-install/main/pacman.conf" > /etc/pacman.conf) &> /dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n " -> sync and make sure latest archlinux keyring is present: " ; pacman -Syy archlinux-keyring --noconfirm &> /dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n " -> running pacstrap: " ; pacstrap /mnt "${packages_to_install[@]}" &> /dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n " -> install pacman.conf for new system: " ; cp /etc/pacman.conf /mnt/etc/pacman.conf &> /dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n " -> rank mirrors for new system: " ; reflector --country Norway,Denmark,Iceland,Finland --protocol https --sort rate --save /mnt/etc/pacman.d/mirrorlist &> /dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
}

clear ; setfont ter-v22n
pre_checks
choose_your_disk
partitioning "$install_disk"
pacstrap_and_configure_pacman

#
#### bootctl --esp-path=/mnt/efi --boot-path=/mnt/boot --efi-boot-option-description="Arch Linux - Autoinstall" install
#