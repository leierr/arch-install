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
	echo -e "\e[33mRunning pre-run checks\e[0m"
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -

	# verify boot mode
	## TESTING PURPOSES
	#echo -n "-> UEFI bootmode: " ;  sleep 0.5 ; [[ -e /sys/firmware/efi/efivars ]] && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	# check internet access
	echo -n "-> Internet access: " ;  sleep 0.5 ; timeout 3 bash -c "</dev/tcp/archlinux.org/443" 2>/dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; }
	# check amd/intel cpu mann
}

function choose_your_disk() {
	local disks_list=($(lsblk -adrnp -o NAME -I 8,259,254))

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
	echo "Partitioning"

	echo "-> wipe & unmount all"
	umount -R /mnt &> /dev/null
	swapoff -a &> /dev/null
	wipefs --force --all $install_disk &> /dev/null
	sleep 1

	echo -n "-> partition disk: "
	sfdisk $install_disk &> /dev/null && echo -e "\e[32mOK\e[0m" || { echo -e "\e[31merr\e[0m"; exit 1; } << EOF
label: gpt
;512Mib;U;*
;512Mib;BC13C2FF-59E6-4262-A352-B275FD6F7172
;+;L
EOF
}

pre_checks
choose_your_disk
partitioning
