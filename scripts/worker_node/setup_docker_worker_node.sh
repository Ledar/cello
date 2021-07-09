#!/usr/bin/env bash

# Copyright IBM Corp, All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

#  This script will help setup Docker at a server, then the server can be used as a worker node.

# Detecting whether can import the header file to render colorful cli output
if [ -f ../header.sh ]; then
	source ../header.sh
elif [ -f scripts/header.sh ]; then
	source scripts/header.sh
else
	echo_r() {
		echo "$@"
	}
	echo_g() {
		echo "$@"
	}
	echo_b() {
		echo "$@"
	}
fi

# collect ID from /etc/os-release as distribution name
# tested on debian,ubuntu,mint , centos,fedora  ,opensuse
get_distribution() {
	distribution="Unknown"
	while read -r line
	do
		element=$(echo $line | cut -f1 -d=)
		if [ "$element" = "ID" ]
		then
			distribution=$(echo $line | cut -f2 -d=)
		fi
		done < "/etc/os-release"
	echo "${distribution//\"}"
}

# Install necessary software including curl, python-pip, tox, docker
install_software() {
	case $DISTRO in
		ubuntu)
			sudo apt-get update && sudo apt-get install -y curl;
			command -v docker >/dev/null 2>&1 || { echo_r >&2 "No docker-engine found, try installing"; curl -sSL https://get.docker.com/ | sh; sudo service docker restart; }
			command -v docker-compose >/dev/null 2>&1 || { echo_r >&2 "No docker-compose found, try installing"; sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; sudo chmod +x /usr/local/bin/docker-compose; }
			;;
		linuxmint)
			sudo apt-get install apt-transport-https ca-certificates -y
			sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
			sudo echo deb https://apt.dockerproject.org/repo ubuntu-xenial main >> /etc/apt/sources.list.d/docker.list
			sudo apt-get update
			sudo apt-get purge lxc-docker
			sudo apt-get install python-pip
			sudo apt-get install linux-image-extra-$(uname -r) -y
			sudo apt-get install docker-engine cgroup-lite apparmor -y
			sudo service docker start
			;;
		debian)
			sudo apt-get install apt-transport-https ca-certificates -y
			sudo sh -c "echo deb https://apt.dockerproject.org/repo debian-jessie main > /etc/apt/sources.list.d/docker.list"
			sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
			sudo apt-get update
			sudo apt-cache policy docker-engine
			sudo apt-get install docker-engine curl python-pip  -y
			sudo service docker start
			;;
		centos)
			sudo yum install -y epel-release yum-utils
			sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
			sudo yum makecache fast
			sudo yum update && sudo yum install -y docker-ce python-pip
			sudo systemctl enable docker
			sudo systemctl start docker
			;;
		fedora)
			sudo dnf -y update
			sudo dnf -y install  docker python-pip --allowerasing
			sudo systemctl enable docker
			sudo systemctl start docker
			;;
		opensuse)
			sudo zypper refresh
			sudo zypper install docker docker-compose python-pip
			sudo systemctl restart docker
			;;
		*)
			echo "Linux distribution not identified !!! skipping docker & pip installation"
			;;
	esac
}

# pull fabric images
#bash ./download_images.sh

echo_b "Copy required fabric 1.0 and 1.1 artifacts"
ARTIFACTS_DIR=/opt/cello
USER=`whoami`
USERGROUP=`id -gn`
DISTRO=$(get_distribution)
MASTER_NODE_IP=192.168.64.5

echo_b "Check curl and docker-engine for $DISTRO"
NEED_INSTALL="false"
for software in curl docker docker-compose; do
	command -v ${software} >/dev/null 2>&1 || { NEED_INSTALL="true"; break; }
done
[ $NEED_INSTALL = "true" ] && install_software

echo_b "Add existing user ${USER} to docker group"
sudo usermod -aG docker ${USER}

if [ `sudo docker ps -qa|wc -l` -gt 0 ]; then
	echo_r "Warn: existing containers may cause unpredictable failure, suggest to clean them (docker rm)"
	docker ps -a
fi

echo_b "Pull fabric images"
sudo docker pull hyperledger/fabric-peer:1.4
sudo docker pull hyperledger/fabric-orderer:1.4
sudo docker pull hyperledger/fabric-ca:1.4

echo_b "Checking local artifacts path ${ARTIFACTS_DIR}..."
[ ! -d ${ARTIFACTS_DIR} ] \
	&& echo_r "Local artifacts path ${ARTIFACTS_DIR} not existed, creating one" \
	&& sudo mkdir -p ${ARTIFACTS_DIR} \
	&& sudo chown -R ${USER}:${USERGROUP} ${ARTIFACTS_DIR}

echo_b "Mount NFS Server ${MASTER_NODE_IP}"
sudo mount -t nfs -o vers=4,loud ${MASTER_NODE_IP}:/ ${ARTIFACTS_DIR}
if [ $? != 0 ]; then
	echo_r "Mount failed"
	exit 1
fi

echo_b "Setup ip forward rules"
sudo sysctl -w net.ipv4.ip_forward=1

echo_g "Setup done"
