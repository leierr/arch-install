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

	[[ -n "${1}" && -e "${1}" && -b "${1}" && ! $(lsblk -dnpo NAME,FSTYPE | grep -P "${1}\s+iso") ]] && return 0

	lsblk -o NAME,SIZE,MOUNTPOINTS,TYPE

	local PS3="Select disk: "
	select disk in ${disk_list[@]} ; do
		[[ -n "$disk" && -e "$disk" && -b "$disk" && ! $(lsblk -dnpo NAME,FSTYPE | grep -P "$disk\s+iso") ]] && break
	done

    install_disk="$disk"
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

	#printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	#sfdisk -lq "$disk"
	#printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -

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
	(mkdir /mnt/etc ; chown root:root /mnt/etc ; chmod 0755 /mnt/etc) &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "├── create etcetera directory: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "├── create etcetera directory: "

	echo -n "└── make fstab: "
	genfstab -U /mnt > /mnt/etc/fstab &> /dev/null || { printf "\r%*s\e[31m%s\e[0m%s\r%s\n" $(($(tput cols) - 7)) "[" "FAILED" "]" "└── make fstab: "; exit 1; }
	printf "\r%*s\e[32m%s\e[0m%s\r%s\n" $(($(tput cols) - 5)) "[  " "OK" "  ]" "└── make fstab: "
}

function pacstrap_and_configure_pacman() {
	echo -e "\033[1m:: Pacstrap ::\033[0m"
	echo -n "├── check cpu type for installing ucode: "
	if [[ $(grep -P "(?<=vendor_id\s\:\s)AuthenticAMD" /proc/cpuinfo) ]] ; then
		packages_to_install+=("amd-ucode")
		ucode="amd"
		echo -e "\e[31m\e[1mAMD\e[0m"
	elif [[ $(grep -P "(?<=vendor_id\s\:\s)GenuineIntel" /proc/cpuinfo) ]] ; then
		packages_to_install+=("intel-ucode")
		ucode="intel"
		echo -e "\e[34m\e[1mINTEL\e[0m"
	else
		echo -e "\e[1m\e[4mN/A\e[0m"
	fi
	echo -n "├── rank mirrors: " ; reflector --country Norway,Denmark,Iceland,Finland --protocol https --sort rate --save /etc/pacman.d/mirrorlist &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── install pacman.conf for live environment: " ; (curl "https://raw.githubusercontent.com/leierr/arch-install/main/pacman.conf" > /etc/pacman.conf) &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── sync: " ; pacman -Syy --noconfirm &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── running pacstrap: " ; pacstrap /mnt "${packages_to_install[@]}" &> /dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── install pacman.conf for new system: " ; cp /etc/pacman.conf /mnt/etc/pacman.conf &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── rank mirrors for new system: " ; reflector --country Norway,Denmark,Iceland,Finland --protocol https --sort rate --save /mnt/etc/pacman.d/mirrorlist &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── initialize pacman keyring for new system: " ; arch-chroot /mnt pacman-key --init &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "└── Populate pacman keyring for new system: " ; arch-chroot /mnt pacman-key --populate archlinux &> /dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
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
	bootctl --esp-path=/mnt/efi --boot-path=/mnt/boot --efi-boot-option-description="Arch Linux" install || { echo -e "[ \e[31mERROR\e[0m ]"; exit 1; }
	echo -e "[ \e[32mOK\e[0m ]"

	echo -n "└── install systemd-boot config file: "
	mkdir -m 755 -p /mnt/boot/loader/entries &> /dev/null
	chown root:root {/mnt/boot,/mnt/boot/loader,/mnt/boot/loader/entries} &> /dev/null
	case $(grep -m 1 -Po "(?<=vendor_id\s\:\s)[A-Za-z]+" /proc/cpuinfo) in
		"AuthenticAMD") echo -e "title Arch Linux\nlinux /vmlinuz-linux-lts\ninitrd /initramfs-linux-lts.img\ninitrd /amd-ucode.img\noptions root=\"LABEL=arch_os\" rw amd_iommu=on\n" > $bootloader_config_file ;;
		"GenuineIntel") echo -e "title Arch Linux\nlinux /vmlinuz-linux-lts\ninitrd /initramfs-linux-lts.img\ninitrd /intel-ucode.img\noptions root=\"LABEL=arch_os\" rw intel_iommu=on\n" > $bootloader_config_file ;;
		*) echo -e "title Arch Linux\nlinux /vmlinuz-linux-lts\ninitrd /initramfs-linux-lts.img\noptions root=\"LABEL=arch_os\" rw\n" > $bootloader_config_file ;;
	esac || { echo -e "[ \e[31mERROR\e[0m ]"; exit 1; }
	echo -e "[ \e[32mOK\e[0m ]"
}

function configure_network() {
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	echo -e "\033[1m:: network ::\033[0m"
	echo -n "├── install /etc/NetworkManager/NetworkManager.conf: "

	mkdir -m 0755 /mnt/etc/NetworkManager &> /dev/null ; chown root:root /mnt/etc/NetworkManager &> /dev/null
	echo -e "[main]\nplugins= \nno-auto-default=*\n" > /mnt/etc/NetworkManager/NetworkManager.conf || { echo -e "\e[31merr\e[0m"; exit 1; }
	chmod 0644 /mnt/etc/NetworkManager/NetworkManager.conf &> /dev/null ; chown root:root /mnt/etc/NetworkManager/NetworkManager.conf &> /dev/null
	echo -e "\e[32mOK\e[0m"
	
	echo -n "└── enable NetworkManager service: " ; arch-chroot /mnt systemctl enable NetworkManager && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
}

function configure_users_and_groups() {
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	echo -e "\033[1m:: configure users and groups ::\033[0m"
	echo -n "└── create user $user_account_name: " ;

	for i in "${user_account_groups[@]}"; do
		[[ $(arch-chroot /mnt getent group "$i") ]] || { arch-chroot /mnt groupadd "$i" ; echo "created group $i" >> "$logfile" ; }
	done

	local useradd_command=("arch-chroot /mnt useradd "$user_account_name" -m")

	[[ -n "${user_account_groups[@]}" ]] && useradd_command+=("-G" "$(echo "${user_account_groups[@]}" | tr ' ' ',')")
	[[ -n "$user_account_home" ]] && useradd_command+=("-d" "$user_account_home")
	[[ -n "$user_account_shell" ]] && useradd_command+=("-s" "$user_account_shell") || useradd_command+=("-s" "/bin/bash")
	[[ -n "$user_account_comment" ]] && useradd_command+=("-c" "'$user_account_comment'")

	${useradd_command[@]} &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
}

function configure_locale() {
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	echo -e "\033[1m:: locale ::\033[0m"
	echo -n "├── install /etc/locale.gen: " ; echo -e "en_US.UTF-8 UTF-8\nnb_NO.UTF-8 UTF-8\n" > /mnt/etc/locale.gen && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "├── install /etc/locale.conf: " ; (curl "https://raw.githubusercontent.com/leierr/arch-install/main/locale.conf" > /mnt/etc/locale.conf) &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	echo -n "└── generate locale: " ; arch-chroot /mnt locale-gen &>> "$logfile" && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
}

function configure_sudoers() {
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	echo -e "\033[1m:: sudoers ::\033[0m"
	echo -n "└── install /etc/sudoers: " ; echo -e "root ALL=(ALL) ALL\nDefaults editor=/bin/vim\nDefaults timestamp_timeout=10\n%wheel ALL=(ALL) NOPASSWD: ALL" > /mnt/etc/sudoers && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
}

clear ; setfont ter-v22b
pre_checks
printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
choose_your_disk "${1}"
printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
partitioning "$install_disk"
printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
pacstrap_and_configure_pacman
bootloader
configure_network
configure_users_and_groups
configure_locale
configure_sudoers
