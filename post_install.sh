#!/bin/sh

AUR_HELPER=''

parse_yaml() {
    result=($(yq "$1" "$2" | sed 's/\"//g' | tr '\n' ' '))
    echo "${result[@]}"
}

get_aur_helper() {
    AUR_HELPER=$(parse_yaml '.aur_helper' 'config.yaml')
    [ $(pacman -Q | grep $AUR_HELPER | wc -l) -gt '0' ] || {
        git clone https://aur.archlinux.org/$AUR_HELPER.git
        cd $AUR_HELPER
        sudo makepkg -si
        cd .. && rm -rf $AUR_HELPER
    }
}

dwd_packages() {
    packages=$(parse_yaml ".$1[]" "packages.yaml")
    [ "$1" -eq "pacman" ] && sudo pacman -S $packages || $AUR_HELPER -S $packages
}

config_dots() {
    dot_repo=$(parse_yaml '.git_repos.dotfiles.https' 'config.yaml')
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
}

create_dirs() {
    dirs=$(parse_yaml '.dirs[]' 'config.yaml')
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
    [ -f "config.yaml" ] || curl -fLO "https://raw.githubusercontent.com/mislavzanic/dotfiles/master/.config/config.yaml"
    get_aur_helper
    create_dirs
    install_packages
    config_dots
    chsh -s $(which zsh)
    cronjobs
    rm -rf config.yaml
    # nvim --headless +PlugInstall +qall
}

while getopts "l" opt; do
    case "$opt" in
        l) laptop="1"
    esac
done

main
[ -z $laptop ] || setup_touchpad
