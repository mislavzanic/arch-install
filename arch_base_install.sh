#!/bin/sh

IS_EFI=''
DEVICE=''
ROOT=''
BOOT=''
SWAP=''
REGION=''
CITY=''
OS=''
DOAS='1'
CMD=''

choose_os() {
    PS3='Choose your base system:'
    select OS in arch artix-openrc artix-runit; do
        break
    done
}

check_efi() {
    [ $(ls /sys/firmware/efi/efivars | wc -l) -gt "0" ] && IS_EFI='1' || IS_EFI='0'
}

check_net() {
    ping -c 1 google.com &> /dev/null
    [ $? -gt "0" ] && echo 'No net.. Please check your network connection.. Aborting..' && exit;
}

get_device() {
    lsblk
    PS3='Choose device for installation:'
    select DEVICE in $(lsblk -dpnoNAME); do
        break
    done
    [ -z $DEVICE ] && DEVICE='/dev/sda' 
}

create_partitions() {
    get_device
    wipefs -a $DEVICE
    sfdisk --delete $DEVICE
    echo 'Swap size (K, M, G...):'
    read swap
    if [ $IS_EFI -eq '1' ]; then
        echo 'Boot partition size (K, M, G...):'
        read boot
fdisk $DEVICE <<EOF
g
n


+550M
n


+$swap
n



t
1
1
t
2
19
w
EOF
    else
        echo 'LEGACY BOOT not supported yet...'
    fi
}

format_disk() {
    parts=($(lsblk -lnpoNAME,TYPE | grep $DEVICE | grep "part" | awk '{print $1}'))
    if [ $IS_EFI -eq '1' ]; then
        BOOT="${parts[0]}"
        SWAP="${parts[1]}"
        ROOT="${parts[2]}"
    else
        SWAP="${parts[0]}"
        ROOT="${parts[1]}"
    fi
    mkfs.ext4 $ROOT
    mkswap $SWAP
    [ $IS_EFI -eq '1' ] && mkfs.fat -F32 $BOOT
    swapon $SWAP
    mount $ROOT /mnt
}

install_base() {
    packages='base linux linux-firmware base-devel vim git yq'
    [ $DOAS -eq '1' ] && packages="$packages doas"
    cmd=''
    case $OS in
        'arch')
            cmd='pacstrap /mnt'
            ;;
        'artix-openrc')
            cmd='basestrap /mnt'
            packages="$packages openrc elogind-openrc"
            ;;
        'artix-runit')
            cmd='basestrap /mnt'
            packages="$packages runit elogind-runit"
            ;;
        *)
            echo "$OS install not supported yet.. aborting.." && exit
            ;;
    esac
    $cmd $packages
}

change_root() {
    CMD=''
    case $OS in
        'arch')
            CMD='arch-chroot'
            ;;
        'artix-openrc')
            CMD='artix-chroot'
            ;;
        'artix-runit')
            CMD='artix-chroot'
            ;;
        *)
            echo "$OS install not supported yet.. aborting.." && exit
            ;;
    esac
    CMD="$CMD /mnt"
}

gen_locale() {
    sed -i '/en_US.UTF-8/s/^#//g' /etc/locale.gen
    locale-gen
}

install_grub() {
    $CMD pacman -S grub dosfstools os-prober mtools
    if [ $IS_EFI -eq "1" ]; then
        $CMD pacman -S efibootmgr 
        mkdir /mnt/boot/EFI
        mount $BOOT /mnt/boot/EFI
        $CMD grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck
        $CMD grub-mkconfig -o /boot/grub/grub.cfg
    else
        echo 'LEGACY BOOT not supported yet...'
    fi
}


configure_user() {
    echo "Enter username..."
    read USER
    $CMD useradd -m $USER
    $CMD passwd $USER
    $CMD usermod -aG wheel,audio,video,storage $USER
    sed -i '/wheel ALL=(ALL) ALL/s/^#//g' /mnt/etc/sudoers
    [ $DOAS -eq '1' ] && touch /mnt/etc/doas.conf && echo "permit :wheel\n permit nopass :wheel as root cmd /usr/bin/tee" | tee /mnt/etc/doas.conf
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
    $CMD pacman -Syyu
    $CMD pacman -S networkmanager
    case $OS in 
        'arch')
            $CMD systemctl enable NetworkManager
            ;;
        'artix-openrc')
            $CMD rc-update add NetworkManager
            ;;
        'artix-runit')
            $CMD ln -s /etc/runit/sv/NetworkManager /run/runit/service
            ;;
        *)
            echo 'Not supported yet... Aborting...' && exit;
    esac
}

main() {
    choose_os
    check_efi
    check_net
    timedatectl set-ntp true
    create_partitions
    format_disk
    install_base
    genfstab -U /mnt >> /mnt/etc/fstab
    change_root
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
    umount -l $DEVICE
    echo "Press enter when ready to reboot and remove boot usb!"
    read DEVICE
    reboot
}

main
