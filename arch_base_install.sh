#!/bin/sh
#
#               _             _     ___           _        _ _
#              / \   _ __ ___| |__ |_ _|_ __  ___| |_ __ _| | | ___ _ __
#             / _ \ | '__/ __| '_ \ | || '_ \/ __| __/ _` | | |/ _ \ '__|
#            / ___ \| | | (__| | | || || | | \__ \ || (_| | | |  __/ |
#           /_/   \_\_|  \___|_| |_|___|_| |_|___/\__\__,_|_|_|\___|_|

IS_EFI=''
DISK=''
ROOT=''
BOOT=''
SWAP=''
REGION=''
CITY=''
OS=''
CMD=''

parse_yaml() {
    result=($(yq "$1" "$2" | sed 's/\"//g' | tr '\n' ' '))
    echo "${result[@]}"
}

check_efi() {
    [ $(ls /sys/firmware/efi/efivars | wc -l) -gt "0" ] && IS_EFI='1' || IS_EFI='0'
}

check_net() {
    ping -c 1 google.com &> /dev/null
    [ $? -gt "0" ] && echo 'No net.. Please check your network connection.. Aborting..' && exit;
}

create_partitions() {
    DISK=$(parse_yaml '.disk' 'config.yaml')
    sgdisk -Z ${DISK}
    sgdisk -a 2048 -o ${DISK}
    sgdisk -n 1::+550MiB --typecode=0:ea00 --change-name=0:'EFI' ${DISK}
    sgdisk -n 2::+2GiB --typecode=0:8200 --change-name=0:'SWAP' ${DISK}
    sgdisk -n 3::-0 --typecode=0:8300 --change-name=0:'ROOT' ${DISK}
}

format_disk() {
    parts=($(lsblk -lnpoNAME,TYPE | grep $DISK | grep "part" | awk '{print $1}'))
    BOOT="${parts[0]}"
    SWAP="${parts[1]}"
    ROOT="${parts[2]}"
    mkfs.ext4 $ROOT
    mkswap $SWAP
    [ $IS_EFI -eq '1' ] && mkfs.fat -F32 $BOOT
    swapon $SWAP
    mount $ROOT /mnt
}

install_base() {
    cmd=''
    packages=$(parse_yaml '.packages.base[]' 'config.yaml')
    [ $OS == 'arch' ] && cmd='pacstrap /mnt' || {
        cmd='basestrap /mnt'
        initsys=$(parse_yaml '.init_system' 'config.yaml')
        packages="$packages $initsys elogind-$initsys"
    }
    $cmd $packages
}

gen_locale() {
    sed -i '/en_US.UTF-8/s/^#//g' /etc/locale.gen
    locale-gen
}

install_grub() {
    mkdir /mnt/boot/EFI
    mount $BOOT /mnt/boot/EFI
    $CMD grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck
    $CMD grub-mkconfig -o /boot/grub/grub.cfg
}


configure_user() {
    USER=$(parse_yaml '.users | keys' 'config.yaml')
    groups=$(parse_yaml ".users.$USER[]" 'config.yaml' | tr ' ' ',')
    $CMD useradd -m $USER
    echo 'Enter user password...  '
    $CMD passwd $USER
    $CMD usermod -aG "$groups" $USER
    sed -i '/wheel ALL=(ALL) ALL/s/^#//g' /mnt/etc/sudoers
    touch /mnt/etc/doas.conf && echo "permit :wheel" | tee /mnt/etc/doas.conf
}

set_localtime() {
    PS3='Choose your Region:'
    select REGION in $(ls /mnt/usr/share/zoneinfo); do
        break
    done

    PS3='Choose your Zone:'
    select CITY in $(ls /mnt/usr/share/zoneinfo/$REGION); do
        break
    done
    echo $REGION" "$CITY
    $CMD ln -sf /usr/share/zoneinfo/$REGION/$CITY /etc/localtime
}

enable_net() {
    initsys=$(parse_yaml '.init_system' 'config.yaml')
    case $initsys in
        'systemd')
            $CMD systemctl enable NetworkManager
            ;;
        'openrc')
            $CMD rc-update add NetworkManager
            ;;
        'runit')
            $CMD ln -s /etc/runit/sv/NetworkManager /run/runit/service
            ;;
        *)
            echo 'Not supported yet... Aborting...' && exit;
    esac
}

main() {
    [ -f 'config.yaml' ] || { echo "Create config.yaml" && exit; }
    check_efi
    check_net
    pacman -S yq
    OS=$(parse_yaml '.os' 'config.yaml')
    CMD="$OS-chroot /mnt"
    timedatectl set-ntp true
    create_partitions
    format_disk
    install_base
    genfstab -U /mnt >> /mnt/etc/fstab
    set_localtime
    $CMD hwclock --systohc
    echo "$HOSTNAME" >> /mnt/etc/hostname
cat <<EOT >> /mnt/etc/hosts
127.0.0.127     localhost
::1             localhost
127.0.1.1       $HOSTNAME.localdomain   $HOSTNAME
EOT
    echo "Enter system password..."
    $CMD passwd 
    configure_user
    install_grub
    enable_net
    echo "Base $OS installed :)"
    umount -l $DISK
    echo "Press enter when ready to reboot and remove boot usb!"
    read DISK
    reboot
}

main
