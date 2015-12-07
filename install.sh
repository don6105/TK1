#!/bin/bash
#Program:
#  Install softwares which defined in installl.conf
#2015/12/07  Author:undersky <don0910129285@gmail.com>

# check root permission
if [ ${EUID} -ne 0 ]; then
	echo "This script must be run as root" 
	exit 1
fi

# check L4T version
VERSION=`head -n 1 /etc/nv_tegra_release`
VERSION="${VERSION:3:2}.${VERSION:27:1}"
echo "L4T R$VERSION"

# ======================================================================
#                         Function defined
# ======================================================================
function Enable_Static_IP(){
	address=(`grep ^address install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}' | sed -e 's/,/\n/g'`)
	netmask=(`grep ^netmask install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}' | sed -e 's/,/\n/g'`)
	gateway=(`grep ^gateway install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}' | sed -e 's/,/\n/g'`)
	dns=(`grep ^dns_server install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}' | sed -e 's/,/\n/g'`)
	
	sudo cp /etc/network/interfaces /etc/network/interfaces.bak
	echo "# interfaces(5) file used by ifup(8) and ifdown(8)" > interfaces
	echo "# Include files from /etc/network/interfaces.d:" >> interfaces
	echo "source-directory /etc/network/interfaces.d" >> interfaces
	echo "" >> interfaces
	echo "auto eth1" >> interfaces
	echo "iface eth1 inet static" >> interfaces
	echo "address ${address}" >> interfaces
	echo "netmask ${netmask}" >> interfaces
	echo "gateway ${gateway}" >> interfaces
	echo "dns-nameservers ${dns}" >> interfaces
	mv interfaces /etc/network/interfaces
	ifdown eth1 && sudo ifup eth1
}

# CPU0 is enabled by default. This function will enabled CPU0~3.
function Enable_Performance(){
	echo "if CPU* already enabled, will return \"Invalid argument\""
	bash -c "echo 0 > /sys/devices/system/cpu/cpuquiet/tegra_cpuquiet/enable"
	bash -c "echo 1 > /sys/devices/system/cpu/cpu0/online"
	bash -c "echo 1 > /sys/devices/system/cpu/cpu1/online"
	bash -c "echo 1 > /sys/devices/system/cpu/cpu2/online"
	bash -c "echo 1 > /sys/devices/system/cpu/cpu3/online"
	bash -c "echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
}

# install build-essential and some common software
function Install_Common(){
	r=`apt-add-repository -y universe`
	r=`apt-get -qq update`
	if [ $? -eq 0 ]; then
		r=`apt-get install -qq -y build-essential sshpass vim`
		if [ $? -eq 0 ]; then
			echo "Install_Common finished.";
			exit 0
		fi
	fi
	echo "Install_Common failed.";
	exit 1
}

# install CUDA6.5
function Install_CUDA(){
	if [ "$VERSION" == "21.4" ] || [ "$VERSION" == "21.3" ]; then
		CUDA_TOOKIT="http://developer.download.nvidia.com/embedded/L4T/r21_Release_v3.0/cuda-repo-l4t-r21.3-6-5-prod_6.5-42_armhf.deb"
	elif [ "$VERSION" == "21.2" ]; then
		CUDA_TOOKIT="http://developer.download.nvidia.com/embedded/L4T/r21_Release_v3.0/cuda-repo-l4t-r$VERSION-6-5-prod_6.5-34_armhf.deb"
	elif [ "$VERSION" == "21.1" ]; then
		CUDA_TOOKIT="http://developer.download.nvidia.com/embedded/L4T/r21_Release_v3.0/cuda-repo-l4t-r$VERSION-6-5-prod_6.5-14_armhf.deb"
	fi
	
	r=`wget -4q $CUDA_TOOKIT -O cuda-6.5_armhf.deb`
	if [ -f cuda-6.5_armhf.deb ]; then
		echo "cuda_toolkit downloaded."
		r=`dpkg -i cuda-6.5_armhf.deb`
		if [ $? -eq 0  ]; then
			r=`apt-get -qq update`
			if [ $? -eq 0  ]; then
				r=`apt-get -qq -y install cuda-toolkit-6-5`
				if [ $? -eq 0  ]; then
					r=`usermod -a -G video $USER`
					if [ $? -eq 0  ]; then
						r=`echo "#CUDA-6.5 bin & library paths:" >> ~/.bashrc`
						r=`echo "export PATH=/usr/local/cuda/bin:\$PATH" >> ~/.bashrc`
						r=`echo "export LD_LIBRARY_PATH=/usr/local/cuda/lib:\$LD_LIBRARY_PATH" >> ~/.bashrc`
						r=`source ~/.bashrc`
						if [ $? -eq 0  ]; then
							r=`rm cuda-6.5_armhf.deb`
							echo "Install_CUDA finished."
							exit 0
						fi
					fi
				fi
			fi
		fi
	fi
	r=`rm cuda-6.5_armhf.deb`
	echo "Install_CUDA failed."
	exit 1
}

function Install_OpenMPI(){
	r=`wget -4q http://www.open-mpi.org/software/ompi/v1.8/downloads/openmpi-1.8.8.tar.gz -O openmpi.tar.gz`
	if [ -f openmpi.tar.gz ]; then
		echo "openmpi.tar.gz downloaded."
		r=`tar -zxf openmpi.tar.gz`
		if [ $? -eq 0  ]; then
			r=`chmod -R 755 openmpi-1.8.8`
			# cd 加反引號`會無法切換目錄
			cd openmpi-1.8.8
			echo "Configure --prefix=/mirror/openmpi-1.8.8 ..."
			r=`./configure --prefix=/mirror/openmpi-1.8.8 &> /dev/null`
			r=`tail -n 1 config.log`
			if [ "${r}" == "configure: exit 0" ]; then
				echo "make all ..."
				r=`make all &> /dev/null || exit 1`
				if [ $? -eq 0  ]; then
					echo "make install ..."
					r=`make install &> /dev/null || exit 1`
					if [ $? -eq 0  ]; then
						r=`echo "#OpenMPI-1.8.8 bin & library paths:" >> ~/.bashrc`
						r=`echo "export PATH=/mirror/openmpi-1.8.8/bin:\$PATH" >> ~/.bashrc`
						r=`echo "export LD_LIBRARY_PATH=/mirror/openmpi-1.8.8/lib:\$LD_LIBRARY_PATH" >> ~/.bashrc`
						r=`source ~/.bashrc`
						if [ $? -eq 0  ]; then
							r=`cd ..`
							r=`rm -rf openmpi-1.8.8 openmpi.tar.gz`
							echo "Install_OpenMPI finished."
							exit 0
						fi
					fi
				fi
			fi
		fi
	fi
	r=`cd ..`
	r=`rm -rf openmpi-1.8.8 openmpi.tar.gz`
	echo "Install_OpenMPI failed."
	exit 1
}

function Install_OpenGL(){
	r=`apt-get -qq -y install build-essential libgl1-mesa-dev libglu1-mesa-dev freeglut3-dev`
	if [ $? -eq 0 ]; then
		echo "Install_OpenGL finished."
		exit 0
	fi
	echo "Install_OpenGL failed."
	exit 1
}

function Install_OpenCV(){
	# if CUDA didn't be installed, call Install_CUDA().
	r=`which nvcc`
	if [ -n "$r" ]; then
		echo "Install_CUDA ..."
		Install_CUDA
	fi
	
	r=`wget -4q http://developer.download.nvidia.com/embedded/OpenCV/L4T_21.2/libopencv4tegra-repo_l4t-r21_2.4.10.1_armhf.deb -O libopencv4tegra_2.4.10.2_armhf.deb`
	if [ -f libopencv4tegra_2.4.10.2_armhf.deb ]; then
		echo "libopencv4tegra_2.4.10.2_armhf.deb downloaded."
		r=`dpkg -i libopencv4tegra_2.4.10.2_armhf.deb`
		if [ $? -eq 0  ]; then
			r=`rm libopencv4tegra_2.4.10.2_armhf.deb`
			echo "Install_OpenCV finished."
			exit 0
		fi
	fi
	r=`rm libopencv4tegra_2.4.10.2_armhf.deb`
	echo "Install_OpenCV failed."
	exit 1
}

function Install_Qt(){
	r=`sudo apt-get -qq -y install qt4-dev-tools libqt4-dev libqt4-core libqt4-gui libqt4-opengl`
	if [ $? -eq 0  ]; then
		echo "Install_Qt4.8 finished."
		exit 0
	fi
	echo "Install_Qt4.8 failed."
	exit 1
}

function Install_Cluster(){
	# transform from installl.conf format to an IP() array
	IP=()
	IFS=',' read -ra ADDR <<< "${Client_IP}"
	#master=1, client start from 2.
	node_k=2
	for i in "${ADDR[@]}"; do
		r=`echo ${i} | grep '-'`
		if [ $? -eq 0 ]; then
			network=`echo ${i} | cut -d '-' -f 1 | cut -d '.' -f 1-3`
			start=`echo ${i} | cut -d '-' -f 1 | cut -d '.' -f 4`
			end=`echo ${i} | cut -d '-' -f 2`
			for j in $(seq ${start} ${end})
			do
				IP+=("${network}.${j} node${node_k}")
				node_k=$((node_k+1))
			done
		else
			IP+=("${i} node${node_k}")
			node_k=$((node_k+1))
		fi
	done
	
	# Avoid password show in history, stop history recording
	set +o history
	
	# Generate hosts file
	echo ""                      > hosts
	echo "#NFS Cluster setting" >> hosts
	echo "${Server_IP} node1"   >> hosts
	for i in "${IP[@]}"
	do
		echo "${i}" >> hosts
	done
	
	
	# =============================================
	#               Master
	# =============================================
	# Check if OpenMPI is installed or not. Call function Install_OpenMPI if it's not installed.
	r=`which mpicc`
	if [ -n "$r" ]; then
		echo "Install_OpenMPI ..."
		Install_OpenMPI
	fi
	# Install software
	r=`apt-get -qq -y install nfs-server`
	# Edit /etc/hosts
	r=`cat hosts >> /etc/hosts`
	# Set login without passwd
	r=`ssh-keygen -q -f file.rsa -t rsa -N ''`
	r=`mv file.rsa ~/.ssh/file.rsa`
	# NFS folder permission
	r=`echo "/mirror*(rw,sync)" | sudo tee –a /etc/exports`
	
	# =============================================
	#               Client
	# =============================================
	for i in "${IP[@]}"
	do
		# ssh -o StrictHostKeyChecking=no : Add it to known hosts when first connect.
		# Copy hosts to all clients
		sshpass -p ${password} scp -o StrictHostKeyChecking=no hosts ${username}@${i}:~ &
		# Copy file.rsa.pub key to all clients
		sshpass -p ${password} scp -o StrictHostKeyChecking=no file.rsa.pub ${username}@${i}:~/.ssh/ &
	done
	#Parallel execute with & and wait
	wait
	
	for i in "${IP[@]}"
	do
		# ssh -o StrictHostKeyChecking=no : Add it to known hosts when first connect.
		# setting all clients
		CMD="hostname -I;"
		CMD="${CMD} set +o history;"
		# Edit /etc/hosts
		CMD="${CMD} echo ${password} | sudo -S bash -c 'cat ~/hosts >> /etc/hosts';"
		# ssh authorized
		CMD="${CMD} touch ~/.ssh/authorized_key;"
		CMD="${CMD} cat ~/.ssh/file.rsa.pub >> ~/.ssh/authorized_key;"
		# apt-get install software
		CMD="${CMD} echo ${password} | sudo -S apt-add-repository -y universe;"
		CMD="${CMD} echo ${password} | sudo -S apt-get update -qq;"
		CMD="${CMD} echo ${password} | sudo -S apt-get install -qq -y nfs-common;"
		# Mounting nfs folder 
		CMD="${CMD} echo ${password} | sudo -S mkdir /mirror;"
		CMD="${CMD} echo ${password} | sudo -S mount ${Server_IP}:/mirror /mirror"
		CMD="${CMD} set -o history;"
		sshpass -p ${password} ssh -o StrictHostKeyChecking=no ${username}@${i} ${CMD} &
	done
	wait
	
	# Restart history recording
	set -o history
	echo "Install_Cluster finished."
}

function Install_Apache(){
	r=`apt-get install -qq -y apache2`
	if [ $? -eq 0 ]; then
		echo "Install_Apache finished."
		exit 0
	fi
	echo "Install_Apache failed."
	exit 1
}
function Install_PHP(){
	r=`apt-get install -qq -y php5 php-pear php5-mysql`
	if [ $? -eq 0 ]; then
		r=`service apache2 restart`
		if [ $? -eq 0 ]; then
			echo "Install_Apache finished."
			exit 0
		fi
	fi
	echo "Install_Apache failed."
	exit 1
}
function Install_MySQL(){
	r=`echo "mysql-server mysql-server/root_password password ${password}" | debconf-set-selections`
	r=`echo "mysql-server mysql-server/root_password_again password ${password}" | debconf-set-selections`
	r=`apt-get install -qq -y mysql-server`
	if [ $? -eq 0 ]; then
		echo "MySQL password for root: ${password}"
		echo "Install_MySQL finished."
		exit 0
	fi
	echo "Install_MySQL failed."
	exit 1
}

# ======================================================================
#                     Read from install.conf file
# ======================================================================
if [ -f "install.conf" ]; then
	username=(`grep -i ^username install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
	password=(`grep -i ^password install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
	
	Static_IP=(`grep -i ^Static_IP install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}' | sed -e 's/,/\n/g'`)
	Performance=(`grep -i ^Enable_Performance install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
	CommonSoftware=(`grep -i ^CommonSoftware install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
	CUDA=(`grep -i ^CUDA6.5 install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
	OpenMPI=(`grep -i ^OpenMPI install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
	OpenGL=(`grep -i ^OpenGL install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
	OpenCV=(`grep -i ^OpenCV install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
	Qt=(`grep -i ^Qt4.8 install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
	
	# Cluster setting
	NFS_Server=(`grep -i ^NFS_Server install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
	Server_IP=(`grep -i ^Server_IP install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
	Client_IP=(`grep -i ^Client_IP install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
	
	# Web
	Apache=(`grep -i ^Apache install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
	PHP=(`grep -i ^PHP install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
	MySQL=(`grep -i ^MySQL install.conf | tr -d ' ' | cut -d = -f 2 | awk '{print tolower($0)}'`)
else
	echo "install.conf: file not found."
	exit 1
fi

# ======================================================================
#                       Call function to do
# ======================================================================
if [ "$Static_IP" == "yes" ]; then
	echo "Prepare setup Static IP......"
	Enable_Static_IP
fi

if [ "$Performance" == "yes" ]; then
	echo "Prepare enable performance......"
	Enable_Performance
fi

if [ "$CommonSoftware" == "yes" ]; then
	echo "Prepare install Common Software......"
	Install_Common
fi

if [ "$CUDA" == "yes" ]; then
	echo "Prepare install CUDA6.5......"
	Install_CUDA
fi

if [ "$OpenMPI" == "yes" ]; then
	echo "Prepare install OpenMPI-1.8.8 ......"
	Install_OpenMPI
fi

if [ "$OpenGL" == "yes" ]; then
	echo "Prepare install OpenGL ......"
	Install_OpenGL
fi

if [ "$OpenCV" == "yes" ]; then
	echo "Prepare install OpenCV ......"
	Install_OpenCV
fi

if [ "$Qt" == "yes" ]; then
	echo "Prepare install Qt4.8 ......"
	Install_Qt
fi

if [ "$NFS_Server" == "yes" ]; then
	echo "Prepare setting Cluster ......"
	Install_Cluster
fi

if [ "$Apache" == "yes" ]; then
	echo "Prepare install Apache ......"
	Install_Apache
fi

if [ "$PHP" == "yes" ]; then
	echo "Prepare install PHP ......"
	Install_PHP
fi

if [ "$MySQL" == "yes" ]; then
	echo "Prepare install MySQL ......"
	Install_MySQL
fi






