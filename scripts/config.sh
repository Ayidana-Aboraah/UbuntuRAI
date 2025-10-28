#!/bin/bash

# This script provides common customization options for the ISO
# 
# Usage: Copy this file to config.sh and make changes there.  Keep this file (default_config.sh) as-is
#   so that subsequent changes can be easily merged from upstream.  Keep all customiations in config.sh

# The version of Ubuntu to generate.  Successfully tested LTS: bionic, focal, jammy, noble
# See https://wiki.ubuntu.com/DevelopmentCodeNames for details
export TARGET_UBUNTU_VERSION="jammy"

export TARGET_ROS_VERSION="humble"

function add_ros_repository() {
    local codename
    codename=$(awk -F= '/^UBUNTU_CODENAME=/{print $2}' /etc/os-release)

    apt-get install -y ca-certificates curl gnupg lsb-release

    case "$TARGET_ROS_VERSION" in
        noetic)
            install -d /usr/share/keyrings
            curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
                | gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg
            # ROS publishes an HTTP endpoint only; HTTPS certificate does not match packages.ros.org
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros/ubuntu ${codename} main" \
                > /etc/apt/sources.list.d/ros1-latest.list
            ;;
        *)
            local ros_apt_release
            ros_apt_release=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | \
                grep -F "tag_name" | awk -F\" '{print $4}')
            curl -L -o /tmp/ros-apt-source.deb \
                "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ros_apt_release}/ros2-apt-source_${ros_apt_release}.${codename}_all.deb"
            dpkg -i /tmp/ros-apt-source.deb
            ;;
    esac
}

function install_ros_packages() {
    local ros_packages=(
        "ros-${TARGET_ROS_VERSION}-desktop-full"
        "ros-${TARGET_ROS_VERSION}-motion-capture-tracking"
        "ros-${TARGET_ROS_VERSION}-turtlebot3"
        "ros-${TARGET_ROS_VERSION}-velodyne*"
        "ros-${TARGET_ROS_VERSION}-pcl-ros"
        "ros-${TARGET_ROS_VERSION}-tf2-ros"
        "ros-${TARGET_ROS_VERSION}-rviz2"
        "ros-${TARGET_ROS_VERSION}-depthai-ros"
        "ros-${TARGET_ROS_VERSION}-glim-ros"
        "ros-dev-tools"
    )

    for pkg in "${ros_packages[@]}"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            apt-get install -y "$pkg"
        else
            echo "Skipping unavailable ROS package $pkg"
        fi
    done    
}

# The Ubuntu Mirror URL. It's better to change for faster download.
# More mirrors see: https://launchpad.net/ubuntu/+archivemirrors
export TARGET_UBUNTU_MIRROR="http://us.archive.ubuntu.com/ubuntu/"

# The packaged version of the Linux kernel to install on target image.
# See https://wiki.ubuntu.com/Kernel/LTSEnablementStack for details
export TARGET_KERNEL_PACKAGE="linux-generic"

# The file (no extension) of the ISO containing the generated disk image,
# the volume id, and the hostname of the live environment are set from this name.
export TARGET_NAME="UbuntuRAI"

# The text label shown in GRUB for booting into the live environment
export GRUB_LIVEBOOT_LABEL="Try UbuntuRAI without installing"

# The text label shown in GRUB for starting installation
export GRUB_INSTALL_LABEL="Install UbuntuRAI"

# Packages to be removed from the target system after installation completes succesfully
export TARGET_PACKAGE_REMOVE="
    ubiquity \
    casper \
    discover \
    laptop-detect \
    os-prober \
"

# Package customisation function.  Update this function to customize packages
# present on the installed system.
function customize_image() {
    # install graphics and desktop
    apt-get install -y \
        plymouth-themes \
        kubuntu-desktop

    # useful tools
    apt-get install -y \
        clamav-daemon \
        terminator \
        tilix \
        apt-transport-https \
        curl \
        vim \
        parallel \
        git \
        nano \
        less

    # Other Imprimis Dependencies
    # apt get install -y \
    #     libgtsam-points-dev \
    #     libiridescence-dev \
    #     libboost-all-dev \
    #     libglfw3-dev \
    #     libmetis-dev


    curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
    install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list
    rm microsoft.gpg
    apt-get update
    apt-get install -y code

    apt-get install -y software-properties-common
    add-apt-repository -y universe
    apt-get update
    add_ros_repository
    apt-get update
    apt-get upgrade -y
    install_ros_packages
    apt-get install -y snapd
    apt-get install -y firefox || true
    apt-get install -y python3-pip || true
    apt-get install -y python3-venv || true

    apt-get install -y --no-install-recommends linux-firmware network-manager

    apt-get install -y shim-signed grub-efi-amd64-signed mokutil sbsigntool

    if apt-cache show linux-generic >/dev/null 2>&1; then
        apt-get install -y linux-generic
    elif grep -q 'VERSION_CODENAME=jammy' /etc/os-release && apt-cache show linux-generic-hwe-22.04 >/dev/null 2>&1; then
        apt-get install -y linux-generic-hwe-22.04
    elif apt-cache show linux-image-generic >/dev/null 2>&1; then
        apt-get install -y linux-image-generic   # also depends on modules-extra versioned pkg
    else
        apt-get install -y linux-virtual || true
    fi

    apt-get install -y --no-install-recommends wireless-tools wpasupplicant iw ubuntu-drivers-common || true

    update-initramfs -u -k all || true
    depmod -a || true

    # purge
    apt-get purge -y \
        transmission-gtk \
        transmission-common \
        gnome-mahjongg \
        gnome-mines \
        gnome-sudoku \
        aisleriot \
        hitori

    apt-get autoremove -y
    
    ROS_SETUP="/opt/ros/${TARGET_ROS_VERSION}/setup.bash"
    cat >/etc/profile.d/ros-setup.sh <<EOL

if [ -f "$ROS_SETUP" ]; then
    . "$ROS_SETUP"
fi
EOL
    chmod 644 /etc/profile.d/ros-setup.sh
    echo "[ -f \"$ROS_SETUP\" ] && . \"$ROS_SETUP\"" >> /etc/skel/.bashrc

apt-get -y autoremove --purge || true
apt-get -y clean || true
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/* || true

snap install firefox || true
}


# Used to version the configuration.  If breaking changes occur, manual
# updates to this file from the default may be necessary.
export CONFIG_FILE_VERSION="0.4"
