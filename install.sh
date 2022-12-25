#!/bin/bash

# local env
install_disk=""
packages_to_install=(
	base base-devel linux-lts linux-lts-headers linux-firmware xfsprogs #required
	vim mousepad # text editors
	noto-fonts-cjk ttf-hack papirus-icon-theme # fonts, icon themes
	firefox # browser of choice
	flameshot # screenshot utility of choice
	bash bash-completion zsh # shell
	cmatrix neofetch htop # just for fun
	curl git wget jq unzip # must have utils
	man-db man-pages # man page support
	lua luarocks python go # programing languages
)

function throw_error() {
	echo -e "\n\e[31mSomething went wrong!\e[0m"
	echo -e "\e[33m$1\e[0m"
	exit 1
}

function choose_your_disk() {
	local disks_list=($(lsblk -adrnp -o NAME -I 8,259))

	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -
	lsblk -o NAME,SIZE,MOUNTPOINTS,TYPE,FSTYPE
	printf "%*s\n" "${COLUMNS:-$(tput cols)}" "" | tr " " -

	select disk in ${disks_list[@]} ; do
		install_disk=$disk
		break
	done

	[[ -n "$install_disk" && -e "$install_disk" ]] && return 0 || throw_error "Disk not found"
}

choose_your_disk