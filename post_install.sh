#!/bin/sh

AUR_HELPER=''

parse_yaml() {
    result=($(yq "$1" "$2" | sed 's/\"//g' | tr '\n' ' '))
    echo "${result[@]}"
}

get_aur_helper() {
    AUR_HELPER=$(parse_yaml '.aur_helper' 'config.yaml')[0]
    [ $(pacman -Q | grep $AUR_HELPER | wc -l) -gt '0' ] || {
        git clone https://aur.archlinux.org/$AUR_HELPER.git
        cd $AUR_HELPER
        sudo makepkg -si
        cd .. && rm -rf $AUR_HELPER
    }
}


dwd_packages() {
    packages=$(yq ".$1[]" packages.yaml | sed 's/\"//g' | tr '\n' ' ')
    [ "$1" -eq "pacman" ] && sudo pacman -S $packages || $AUR_HELPER -S $packages
}

config_dots() {
    dot_repo=$(parse_yaml '.dotfiles[]' 'config.yaml')[0]
    git clone --recurse-submodules "$dot_repo" $HOME/dotfiles
    chmod a+x $HOME/dotfiles/install.sh
    $HOME/dotfiles/install.sh
    rm -rf ~/dotfiles
}

setup_touchpad() {
    sudo touch /etc/X11/xorg.conf.d/50-libinput.conf
    sudo tee -a /etc/X11/xorg.conf.d/50-libinput.conf > /dev/null <<EOF
Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
        Option "Tapping" "on"
        Option "DisableWhileTyping" "on"
EndSection
EOF
}

install_packages() {
    dwd_packages "packages.pacman"
    dwd_packages "packages.aur"
    config_dots
}

create_dirs() {
    dirs=($(yq ".dirs[]" | sed 's/\"//g' | tr '\n' ' '))
    for dir in "${dirs[@]}"; do
        mkdir -p $dir
    done
}

cronjobs() {
   sudo touch /var/spool/cron/root
   /usr/bin/crontab /var/spool/cron/root
   echo "0 */2 * * * /usr/bin/pacman -Syyw" >> /var/spool/cron/root
}

main() {
    [ -f "config.yaml" ] || curl -fLO "https://raw.githubusercontent.com/mislavzanic/arch_install/master/config.yaml"
    get_aur_helper
    create_dirs
    install_packages "$1"
    chsh -s $(which zsh)
    cronjobs
    # nvim --headless +PlugInstall +qall
}

while getopts "l" opt; do
    case "$opt" in
        l) laptop="1"
    esac
done

main
[ -z $laptop ] || setup_touchpad
