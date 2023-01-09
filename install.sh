#!/bin/bash

user_account_name="leier"
user_account_groups=("adm" "wheel")
user_account_home="" # default /home/username
user_account_shell="" # default bash
user_account_comment=""
user_account_sudo_nopw=true # IMPLEMENT DA
# --- #
install_disk=""
# --- #
declare -a packages_to_install=(
	"base" "base-devel" "linux-lts" "linux-lts-headers" "linux-firmware" "xfsprogs" #required
	"vim" "mousepad" # text editors
	"noto-fonts-cjk" "ttf-hack" "papirus-icon-theme" # fonts, icon themes
	"firefox" # browser of choice
	"flameshot" # screenshot utility of choice
	"bash" "bash-completion" "starship" # shell
	"networkmanager" # network managment
	"cmatrix" "neofetch" "htop" # just for fun
	"curl" "git" "wget" "jq" "unzip" # must have utils
	"man-db" "man-pages" # man page support
	"lua" "luarocks" "python" "go" # programing languages
)

function pre_checks () {
	echo -e "\033[1m:: Running pre-run checks ::\033[0m"
	# verify boot mode
	echo -n "├── UEFI bootmode: "
	[[ -e /sys/firmware/efi/efivars ]] &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── UEFI bootmode: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── UEFI bootmode: "

	# check internet access
	echo -n "└── Internet access: "
	timeout 3 bash -c "</dev/tcp/archlinux.org/443" &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "└── Internet access: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "└── Internet access: "
}

function choose_your_disk() {
	local disk_list=($(lsblk -dnpo NAME -I 8,259,254,179 | grep -Pv "mmcblk\dboot\d"))

	# checks if disk was supplied through arguments
	[[ -n "${1}" && -e "${1}" && -b "${1}" && ! $(lsblk -dnpo NAME,FSTYPE | grep -P "${1}\s+iso") ]] && return 0

	# pretty print disks
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	lsblk -o NAME,SIZE,MOUNTPOINTS,TYPE
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -

	# remove arch iso from disk list
	for i in ${!disk_list[@]} ; do
		local archiso=$(lsblk -dnpo NAME,FSTYPE | grep -Po "/dev/[a-z]*(?=\s+iso)")
		if [ "${disk_list[$i]}" == "$archiso" ]; then
			unset disk_list[$i]
		fi
	done

	local PS3="Select disk: "
	select disk in ${disk_list[@]} ; do
		[[ -n "$disk" && -e "$disk" && -b "$disk" ]] && break
	done
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -

    install_disk="$disk"
	clear
    return 0
}

function partitioning() {
	local disk="${1}"
	echo -e "\033[1m:: Partitioning ::\033[0m"

	# ensure that disk is clean before we begin partitioning
	echo -n "├── wipe & unmount all: "
	umount -AR /mnt &> /dev/null
	swapoff -a &> /dev/null
	wipefs -af "$disk" &> /dev/null
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── wipe & unmount all: "

	# partition disk
	echo -n "└── partition disk: "
	echo -e "label: gpt\n;512Mib;U;*\n;512Mib;BC13C2FF-59E6-4262-A352-B275FD6F7172\n;+;L" | sfdisk "$disk" &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "└── partition disk: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "└── partition disk: "

	# registrer partitions
	local disk_partitions=($(sfdisk -lq "$disk" | grep -Po '^/dev/.*?\s'))
	local boot_partition="${disk_partitions[0]}"
	local extended_boot_partition="${disk_partitions[1]}"
	local root_partition="${disk_partitions[2]}"
	[[ ${#disk_partitions[@]} -eq 3 && -n ${disk_partitions[@]} ]] || { echo "something went wrong when saving new partitions to variable"; exit 1; }

	# filesystems
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	echo -e "\033[1m:: Filesystems ::\033[0m"

	echo -n "├── boot partition: "
	mkfs.fat -IF 32 "$boot_partition" &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── boot partition: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── boot partition: "

	echo -n "├── extended boot partition: "
	mkfs.fat -IF 32 "$extended_boot_partition" &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── extended boot partition: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── extended boot partition: "

	echo -n "├── root partition: "
	mkfs.xfs -fL "arch_os" "$root_partition" &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── root partition: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── root partition: "

	echo -n "├── mounting root partition: "
	mount "$root_partition" /mnt &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── mounting root partition: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── mounting root partition: "

	echo -n "├── creating folders for mounting: "
	mkdir /mnt/{efi,boot} &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── creating folders for mounting: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── creating folders for mounting: "
	
	echo -n "├── mounting boot partition: "
	mount "$boot_partition" /mnt/efi &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── mounting boot partition: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── mounting boot partition: "

	echo -n "├── mounting extended boot partition: "
	mount "$extended_boot_partition" /mnt/boot &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── mounting extended boot partition: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── mounting extended boot partition: "

	echo -n "├── create etcetera directory: "
	(mkdir /mnt/etc ; chown root:root /mnt/etc ; chmod 0755 /mnt/etc) &> /dev/null
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── create etcetera directory: "

	echo -n "└── make fstab: "
	genfstab -U /mnt > /mnt/etc/fstab || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "└── make fstab: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "└── make fstab: "
}

function pacstrap_and_configure_pacman() {
	echo -e "\033[1m:: Pacstrap ::\033[0m"

	echo -n "├── check cpu type for installing ucode: "
	case $(grep -m 1 -Po "(?<=vendor_id\s\:\s)[A-Za-z]+" /proc/cpuinfo) in

		"AuthenticAMD")
			packages_to_install+=("amd-ucode")
			printf "\r%*s\033[1m\e[31m%s\e[0m\033[0m%s\r%s\n" $(($(tput cols) - 5)) "[ " "AMD" " ]" "├── check cpu type for installing ucode: "
			;;

		"GenuineIntel")
			packages_to_install+=("intel-ucode")
			printf "\r%*s\033[1m\e[34m%s\e[0m\033[0m%s\r%s\n" $(($(tput cols) - 7)) "[ " "INTEL" " ]" "├── check cpu type for installing ucode: "
			;;

		*)
			printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── check cpu type for installing ucode: "
			;;
	esac || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── check cpu type for installing ucode: "; exit 1; }

	echo -n "├── rank mirrors: "
	reflector --country Norway,Denmark,Iceland,Finland --protocol https --sort rate --save /etc/pacman.d/mirrorlist &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── rank mirrors: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── rank mirrors: "

	echo -n "├── install pacman.conf for live environment: "
	curl "https://raw.githubusercontent.com/leierr/arch-install/main/pacman.conf" &>/dev/null > /etc/pacman.conf || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── install pacman.conf for live environment: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── install pacman.conf for live environment: "

	echo -n "├── sync: "
	pacman -Syy --noconfirm &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── sync: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── sync: "

	echo -n "├── running pacstrap: "
	pacstrap /mnt "${packages_to_install[@]}" &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── running pacstrap: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── running pacstrap: "

	echo -n "├── install pacman.conf for new system: "
	cp /etc/pacman.conf /mnt/etc/pacman.conf || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── install pacman.conf for new system: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── install pacman.conf for new system: "

	echo -n "├── rank mirrors for new system: "
	reflector --country Norway,Denmark,Iceland,Finland --protocol https --sort rate --save /mnt/etc/pacman.d/mirrorlist &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── rank mirrors for new system: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── rank mirrors for new system: "

	echo -n "├── initialize pacman keyring for new system: "
	arch-chroot /mnt pacman-key --init &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── initialize pacman keyring for new system: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── initialize pacman keyring for new system: "

	echo -n "└── Populate pacman keyring for new system: "
	arch-chroot /mnt pacman-key --populate archlinux &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "└── Populate pacman keyring for new system: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "└── Populate pacman keyring for new system: "
}

function bootloader() {
	local boot="/mnt/efi"
	local extended_boot="/mnt/boot"
	local bootloader_config_file="/mnt/boot/loader/entries/arch.conf"

	echo -e "\033[1m:: systemd-boot ::\033[0m"

	# check for that /efi and /boot are present.
	echo -n "├── checks: "
	[[ -e "$boot" && -e "$extended_boot" && $(findmnt -M "$boot") && $(findmnt -M "$extended_boot") ]] || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── checks: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── checks: "

	echo -n "├── install systemd-boot: "
	bootctl --esp-path=/mnt/efi --boot-path=/mnt/boot --efi-boot-option-description="Arch Linux" install &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── install systemd-boot: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── install systemd-boot: "

	echo -n "└── install systemd-boot config file: "
	mkdir -m 755 -p /mnt/boot/loader/entries &> /dev/null
	chown root:root {/mnt/boot,/mnt/boot/loader,/mnt/boot/loader/entries} &> /dev/null
	case $(grep -m 1 -Po "(?<=vendor_id\s\:\s)[A-Za-z]+" /proc/cpuinfo) in
		"AuthenticAMD")
			echo -e "title Arch Linux\nlinux /vmlinuz-linux-lts\ninitrd /initramfs-linux-lts.img\ninitrd /amd-ucode.img\noptions root=\"LABEL=arch_os\" rw\n" > $bootloader_config_file
			;;
		"GenuineIntel")
			echo -e "title Arch Linux\nlinux /vmlinuz-linux-lts\ninitrd /initramfs-linux-lts.img\ninitrd /intel-ucode.img\noptions root=\"LABEL=arch_os\" rw\n" > $bootloader_config_file
			;;
		*)
			echo -e "title Arch Linux\nlinux /vmlinuz-linux-lts\ninitrd /initramfs-linux-lts.img\noptions root=\"LABEL=arch_os\" rw\n" > $bootloader_config_file
			;;
	esac || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "└── install systemd-boot config file: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "└── install systemd-boot config file: "
}

function configure_network() {
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	echo -e "\033[1m:: network ::\033[0m"

	echo -n "├── install /etc/NetworkManager/NetworkManager.conf: "
	mkdir -m 0755 /mnt/etc/NetworkManager &> /dev/null
	chown root:root /mnt/etc/NetworkManager &> /dev/null
	echo -e "[main]\nplugins= \nno-auto-default=*\n" > /mnt/etc/NetworkManager/NetworkManager.conf || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── install /etc/NetworkManager/NetworkManager.conf: "; exit 1; }
	chmod 0644 /mnt/etc/NetworkManager/NetworkManager.conf &> /dev/null
	chown root:root /mnt/etc/NetworkManager/NetworkManager.conf &> /dev/null
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── install /etc/NetworkManager/NetworkManager.conf: "
	
	echo -n "└── enable NetworkManager service: "
	arch-chroot /mnt systemctl enable NetworkManager || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "└── enable NetworkManager service: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "└── enable NetworkManager service: "
}

function configure_users_and_groups() {
	echo -e "\033[1m:: configure users and groups ::\033[0m"

	echo -n "├── create user: $user_account_name"

	for i in "${user_account_groups[@]}"; do
		[[ $(arch-chroot /mnt getent group "$i") ]] || arch-chroot /mnt groupadd "$i" || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── create user: $user_account_name"; exit 1; }
	done

	local useradd_command=("arch-chroot /mnt useradd "$user_account_name" -m")

	[[ -n "${user_account_groups[@]}" ]] && useradd_command+=("-G" "$(echo "${user_account_groups[@]}" | tr ' ' ',')")
	[[ -n "$user_account_home" ]] && useradd_command+=("-d" "$user_account_home")
	[[ -n "$user_account_shell" ]] && useradd_command+=("-s" "$user_account_shell") || useradd_command+=("-s" "/bin/bash")
	[[ -n "$user_account_comment" ]] && useradd_command+=("-c" "'$user_account_comment'")

	${useradd_command[@]} &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── create user: $user_account_name"; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── create user: $user_account_name"

	echo -n "└── unlock user: $user_account_name"
	passwd -d "$user_account_name" || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "└── unlock user: $user_account_name"; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "└── unlock user: $user_account_name"
}

function configure_locale() {
	echo -e "\033[1m:: locale ::\033[0m"

	echo -n "├── install /etc/locale.gen: "
	echo -e "en_US.UTF-8 UTF-8\nnb_NO.UTF-8 UTF-8\n" > /mnt/etc/locale.gen || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── install /etc/locale.gen: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── install /etc/locale.gen: "

	echo -n "├── install /etc/locale.conf: "
	curl "https://raw.githubusercontent.com/leierr/arch-install/main/locale.conf" &>/dev/null > /mnt/etc/locale.conf || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── install /etc/locale.conf: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── install /etc/locale.conf: "

	echo -n "└── generate locale: "
	arch-chroot /mnt locale-gen &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "└── generate locale: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "└── generate locale: "
}

function configure_sudoers() {
	echo -e "\033[1m:: sudoers ::\033[0m"

	echo -n "└── install /etc/sudoers: "
	echo -e "root ALL=(ALL) ALL\nDefaults editor=/bin/vim\nDefaults timestamp_timeout=10\n%wheel ALL=(ALL) NOPASSWD: ALL" > /mnt/etc/sudoers || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "└── install /etc/sudoers: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "└── install /etc/sudoers: "
}

clear ; setfont ter-v22b
choose_your_disk "${1}"
pre_checks
partitioning "$install_disk"
pacstrap_and_configure_pacman
bootloader
configure_network
configure_users_and_groups
configure_locale
configure_sudoers
