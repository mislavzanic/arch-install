#!/bin/sh

get_aur_helper() {
    git clone https://aur.archlinux.org/paru.git
    cd paru
    sudo makepkg -si
    cd .. && rm -rf paru
}


dwd_packages() {
    packages=$(yq ".$1[]" packages.yaml | sed 's/\"//g' | tr '\n' ' ')
    [ "$1" -eq "pacman" ] && sudo pacman -S $packages || paru -S $packages
}

config_dots() {
    git clone --recurse-submodules https://github.com/mislavzanic/dotfiles.git $HOME/dotfiles
    chmod a+x $HOME/dotfiles/install.sh
    $HOME/dotfiles/install.sh
    rm -rf ~/dotfiles
    git clone https://github.com/mislavzanic/scripts.git $HOME/.local/bin/scripts
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
    [ $(pacman -Q | grep paru | wc -l) -gt '0' ] || get_aur_helper
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
    create_dirs
    install_packages $1
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
