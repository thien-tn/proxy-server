 #!/usr/bin/env bash

# Author - akmaslov-dev
# Modified by ThienTranJP
# Simple script to setup dante socks proxy server
# Should work on Debian, Ubuntu and CentOS

# Check for bash shell
if readlink /proc/$$/exe | grep -qs "dash"; then
	echo "This script needs to be run with bash, not sh"
	exit 1
fi

# Checking for root permission
if [[ "$EUID" -ne 0 ]]; then
	echo "Sorry, but you need to run this script as root"
	exit 2
fi

# Checking for distro type (Debian, Ubuntu or CentOS)
if [[ -e /etc/debian_version ]]; then
	OStype=deb
elif [[ -e /etc/centos-release || -e /etc/redhat-release ]]; then
	OStype=centos
else
	echo "You should only run this installer on Debian, Ubuntu or CentOS"
	exit 3
fi

# Obtaining name for system LAN interface
interface="$(ip -o -4 route show to default | awk '{print $5}')"
# Kiểm tra xem giao diện có tồn tại không
if [[ -n "$interface" && -d "/sys/class/net/$interface" ]]; then
	echo "Interface $interface exists."
else
	echo "Interface does not exist."
fi


# Checking for previous installation with this script
if [[ -e /etc/sockd.conf ]]; then
    while : ; do
	clear
		echo "Dante socks proxy is already installed."
		echo " "
		echo "What do you want to do now?"
		echo "	1) Xem danh sách proxy hiện có"
		echo "	2) Thêm một proxy user mới"
		echo "	3) Xóa một proxy user"
		echo "	4) Xóa toàn bộ proxy user"
		echo "	5) Thay đổi giới hạn tốc độ proxy"
		echo "	6) Xóa toàn bộ cấu hình server proxy & user"
		echo "	7) Exit"
		read -p "Select an option [1-7]: " option
		case $option in
			1)
				echo "Current proxy list:"
				
				# Hiển thị danh sách người dùng được thêm vào hệ thống cho proxy
				awk -F: '$3 > 1000 && $7 == "/usr/sbin/nologin" && $1 != "nobody" {print $1}' /etc/passwd
				
				# Dừng lại cho tới khi người dùng nhấn Enter để tiếp tục
				echo " "
				read -p "Press Enter to return to menu..."
				;;
			2)
				# Creating new user for proxy
				echo " "
				# Getting new Login
				read -p "Please enter the name for new proxy user: " -e -i proxyuser usernew
				echo " "
				# Getting new password for new user
				while true; do
					read -s -p "Now we need a VERY, VERY STRONG PASSWORD for new proxy user: " passwordnew
					echo " "
					read -s -p "Please retype your password (again): " passwordnew2
					echo " "
					[ "$passwordnew" = "$passwordnew2" ] && break
					echo "Password and password confirmation does not match"
					echo " "
					echo "Please try again"
					echo " "
				done
				# Check if user name is not empty
				if [[ -z "$usernew" ]]; then
					echo "Error: Username cannot be empty."
					exit 1
				fi
				# Creating new proxy user
				useradd -M -s /usr/sbin/nologin -p "$(openssl passwd -1 "$passwordnew")" "$usernew"
				echo " "
				echo "New user added!"
				echo " "
				read -p "Press Enter to return to menu..."
				;;
			3)
				echo "Current proxy user:"				
				# Hiển thị danh sách người dùng được thêm vào hệ thống cho proxy
				awk -F: '$3 > 1000 && $7 == "/usr/sbin/nologin" && $1 != "nobody" {print $1}' /etc/passwd
				# Deleting an existing user
				read -p "Please enter the name of the user to delete: " deluser
				echo " "
				if getent passwd "$deluser" > /dev/null 2>&1; then
					userdel "$deluser"
					echo "User $deluser deleted!"
				else
					echo "Cannot find user with this name!"
				fi
				echo " "
				read -p "Press Enter to return to menu..."
				;;
			4)
				# In danh sách người dùng có UID > 1000, sử dụng shell /usr/sbin/nologin, trừ người dùng 'nobody'
				echo "The following users have UID > 1000, use /usr/sbin/nologin, and will be deleted (excluding 'nobody'):"

				# Liệt kê các người dùng có UID > 1000, shell /usr/sbin/nologin, trừ 'nobody'
				awk -F: '$3 > 1000 && $7 == "/usr/sbin/nologin" && $1 != "nobody" {print $1}' /etc/passwd

				# Xác nhận lại trước khi xóa
				read -p "Are you sure you want to delete these users? [y/N]: " confirmation
				if [[ "$confirmation" != "y" ]]; then
				echo "Operation cancelled."
				exit 0
				fi

				# Xóa người dùng có UID > 1000, shell /usr/sbin/nologin, trừ người dùng 'nobody'
				awk -F: '$3 > 1000 && $7 == "/usr/sbin/nologin" && $1 != "nobody" {print $1}' /etc/passwd | while read -r user; do
				userdel -r "$user"
				echo "Deleted user: $user"
				done

				echo "All specified users have been deleted."
				echo " "
				read -p "Press Enter to return to menu..."
				;;
			5)
				
				# Lấy thông tin tốc độ hiện tại
				current_limit=$(tc -s class show dev $interface | grep "class htb 1:1" | grep -oP 'rate \K[0-9]+[a-zA-Z]+')

				# Nếu không có tốc độ hiện tại, gán giá trị mặc định
				if [[ -z "$current_limit" ]]; then
					echo "No current speed limit found."
				else
					echo "Current proxy speed limit is: $current_limit"
				fi

				# Nhập tốc độ giới hạn mới
				echo "Enter new limit in Mbps (e.g., 100 for 100Mbps):"
				read -p "New limit: " newlimit

				# Xóa cấu hình traffic control hiện tại
				tc qdisc del dev $interface root

				# Thiết lập traffic control với giới hạn mới
				tc qdisc add dev $interface root handle 1: htb default 30
				tc class add dev $interface parent 1: classid 1:1 htb rate ${newlimit}mbit ceil ${newlimit}mbit
				tc class add dev $interface parent 1:1 classid 1:30 htb rate ${newlimit}mbit ceil ${newlimit}mbit

				# Áp dụng bộ lọc cho traffic control
				tc filter add dev $interface protocol ip parent 1:0 prio 1 u32 match ip src 0.0.0.0/0 flowid 1:30
				tc filter add dev $interface protocol ip parent 1:0 prio 1 u32 match ip dst 0.0.0.0/0 flowid 1:30

				# Thông báo giới hạn mới đã được áp dụng
				echo "Traffic limit updated to ${newlimit}Mbps"
				echo " "
				read -p "Press Enter to return to menu..."
				;;
			6)
				echo " "
				read -p "Do you really want to remove Dante socks proxy server? [y/n]: " -e -i n REMOVE
				if [[ "$REMOVE" = 'y' ]]; then
					if [[ "$OStype" = 'deb' ]]; then
						# If deb based distro
						systemctl stop sockd
						update-rc.d -f sockd remove
						rm -f /etc/init.d/sockd
						rm -f /etc/sockd.conf
						rm -f /usr/sbin/sockd
						echo " "
						echo "Dante socks proxy server deleted!"
					else
						# If CentOS
						systemctl stop sockd
						systemctl disable sockd
						rm -f /etc/systemd/system/sockd.service
						rm -f /usr/sbin/sockd
						rm -f /etc/sockd.conf
						systemctl daemon-reload
						systemctl reset-failed
						# Checking for firewalld
						if pgrep firewalld > /dev/null; then
							delport="$(grep 'port =' /etc/sockd.conf | awk '{print $5}')"
							firewall-cmd --zone=public --remove-port="$delport"/tcp
							firewall-cmd --zone=public --remove-port="$delport"/udp
							firewall-cmd --runtime-to-permanent
							firewall-cmd --reload
						fi
						echo " "
						echo "Dante socks proxy server deleted!"
					fi
				else
					echo " "
					echo "Removal process aborted!"
				fi

				# Xóa người dùng có UID > 1000, shell /usr/sbin/nologin, trừ người dùng 'nobody'
				awk -F: '$3 > 1000 && $7 == "/usr/sbin/nologin" && $1 != "nobody" {print $1}' /etc/passwd | while read -r user; do
				userdel -r "$user"
				echo "Deleted user: $user"
				done
				
				echo " "
				read -p "Press Enter to return to menu..."
				;;
			7)
				# Just exit this script
				echo "Exiting..."
				exit 0
				;;
		esac
	done
else
	clear

	# Kiểm tra nếu người dùng nhập vào port hợp lệ
	while true; do
		read -p "Please enter the port number for our proxy server:  " -e -i 1080 port
		if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
			break
		else
			echo "Invalid input! Please enter a valid port number (1-65535)."
		fi
	done
	echo " "

    # Kiểm tra và mở cổng với UFW và iptables
    # Check if UFW is active and open the specified port if needed
    if sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow "$port"/tcp
        echo "Port $port opened in UFW."
    else
        echo "UFW is not active or port $port is already open."
    fi

    # Check if iptables is active and open the specified port if needed
    if sudo iptables -L | grep -q "ACCEPT     tcp  --  anywhere             anywhere             tcp dpt:$port"; then
        echo "Port $port is already open in iptables."
    else
        sudo iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        echo "Port $port opened in iptables."
    fi    

	# Kiểm tra nếu người dùng nhập vào số lượng proxy hợp lệ
	while true; do
		read -p "Please enter the number of proxies to create: " -e numofproxy
		if [[ "$numofproxy" =~ ^[0-9]+$ ]] && [ "$numofproxy" -ge 1 ]; then
			break
		else
			echo "Invalid input! Please enter a valid number of proxies (greater than 0)."
		fi
	done
	echo " "

    # Hỏi người dùng về giới hạn băng thông (Mbps) và kiểm tra đầu vào
    while true; do
        read -p "Please enter the bandwidth limit in Mbps (e.g., 100 for 100Mbps): " limit

        # Kiểm tra nếu người dùng nhập vào là một số hợp lệ
        if [[ "$limit" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "Invalid input! Please enter a valid number."
        fi
    done
	
	# Generate random username and password for each proxy
	for i in $(seq 1 $numofproxy); do
		user[$i]=$(openssl rand -base64 8 | tr -dc 'a-zA-Z' | head -c 8)
		password[$i]=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
	done

	# Installing minimal requirements
	if [[ "$OStype" = 'deb' ]]; then
		# If deb based distro
		apt-get update
		apt-get -y install openssl make gcc
	else
		# Else, the distro is CentOS
		yum -y install epel-release
		yum -y install openssl make gcc
	fi

	# Getting Dante 1.4.3
	wget https://www.inet.no/dante/files/dante-1.4.3.tar.gz
	# Unpacking
	tar xvfz dante-1.4.3.tar.gz && cd dante-1.4.3 || exit 4
	# Configuring Dante
	./configure \
	--prefix=/usr \
	--sysconfdir=/etc \
	--localstatedir=/var \
	--disable-client \
	--without-libwrap \
	--without-bsdauth \
	--without-gssapi \
	--without-krb5 \
	--without-upnp \
	--without-pam
	# Compiling Dante
	make && make install

	# Creating /etc/sockd.conf
	cat > /etc/sockd.conf <<-EOF
	internal: $interface port = $port
	external: $interface
	user.privileged: root
	user.unprivileged: nobody
	socksmethod: username
	logoutput: /var/log/sockd.log
	client pass {
		from: 0.0.0.0/0 to: 0.0.0.0/0
		log: error
		socksmethod: username
	}
	socks pass {
		from: 0.0.0.0/0 to: 0.0.0.0/0
		command: bind connect udpassociate
		log: error
		socksmethod: username
	}
	EOF

	# Creating new users for proxy
	for i in $(seq 1 $numofproxy); do
		# Check if username is valid
		if [[ -z "${user[$i]}" ]]; then
			echo "Error: Generated username is empty. Skipping user $i."
			continue
		fi
		useradd -M -s /usr/sbin/nologin "${user[$i]}"
		echo "${user[$i]}:${password[$i]}" | chpasswd
	done

	# Creating services
	if [[ "$OStype" = 'deb' ]]; then
		# Creating sockd daemon for Debian/Ubuntu
		cat > /etc/systemd/system/sockd.service <<-'EOF'
		[Unit]
		Description=Dante Socks Proxy v1.4.3
		After=network.target

		[Service]
		Type=forking
		PIDFile=/var/run/sockd.pid
		ExecStart=/usr/sbin/sockd -D -f /etc/sockd.conf
		ExecReload=/bin/kill -HUP $MAINPID
		KillMode=process
		Restart=on-failure

		[Install]
		WantedBy=multi-user.target
		EOF

		# Restarting systemctl daemon
		systemctl daemon-reload
		# Enabling autostart for sockd service
		systemctl enable sockd
		# Starting sockd daemon
		systemctl start sockd
	else
		# Creating systemctl service for CentOS
		cat > /etc/systemd/system/sockd.service <<-'EOF'
		[Unit]
		Description=Dante Socks Proxy v1.4.3
		After=network.target

		[Service]
		Type=forking
		PIDFile=/var/run/sockd.pid
		ExecStart=/usr/sbin/sockd -D -f /etc/sockd.conf
		ExecReload=/bin/kill -HUP $MAINPID
		KillMode=process
		Restart=on-failure

		[Install]
		WantedBy=multi-user.target
		EOF

		# Restarting systemctl daemon
		systemctl daemon-reload
		# Enabling autostart for sockd service
		systemctl enable sockd
		# Starting service
		systemctl start sockd
	fi

	# Set up traffic control (tc) for bandwidth limitation với limit người dùng nhập vào
	tc qdisc add dev $interface root handle 1: htb default 30
	tc class add dev $interface parent 1: classid 1:1 htb rate ${limit}mbit ceil ${limit}mbit
	tc class add dev $interface parent 1:1 classid 1:30 htb rate ${limit}mbit ceil ${limit}mbit

	# Giới hạn toàn bộ traffic qua $interface với giá trị $limit Mbps
	tc filter add dev $interface protocol ip parent 1:0 prio 1 u32 match ip src 0.0.0.0/0 flowid 1:30
	tc filter add dev $interface protocol ip parent 1:0 prio 1 u32 match ip dst 0.0.0.0/0 flowid 1:30

	# In ra thông báo xác nhận giới hạn băng thông đã được thiết lập
	echo "Traffic control applied, limiting to ${limit}Mbps for upload and download"

	# Tạo tệp proxy với định dạng IP:PORT:LOGIN:PASS
	gen_proxy_file_for_user() {
		# Sử dụng một vòng lặp thông thường và redirect đầu ra vào tệp proxy.txt
		> proxy.txt  # Tạo hoặc làm trống tệp proxy.txt nếu nó đã tồn tại
		for i in $(seq 1 $numofproxy); do
			echo "$hostname:$port:${user[$i]}:${password[$i]}" >> proxy.txt
		done
	}

	
	install_zip_jq() {
		# install zip
		sudo apt-get install zip -y

		# install jq
		sudo apt-get install jq -y
	}

	# Nén tệp proxy và upload lên download server
	upload_2file() {
		local PASS=$(openssl rand -base64 12)  # Tạo mật khẩu ngẫu nhiên
		zip --password "$PASS" proxy.zip proxy.txt
		JSON=$(curl -F "file=@proxy.zip" https://file.io)
		URL=$(echo "$JSON" | jq --raw-output '.link')

		echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
		echo "Download zip archive from: ${URL}"
		echo "Password: ${PASS}"
	}

	# Sau khi tạo người dùng proxy xong

	# Output proxy list to console
	hostname=$(hostname -I | awk '{print $1}')
	echo "Proxy list (IP:PORT:LOGIN:PASS):"
	for i in $(seq 1 $numofproxy); do
		if [[ -n "${user[$i]}" ]]; then
			echo "$hostname:$port:${user[$i]}:${password[$i]}"
		fi
	done

	# Tạo và upload tệp proxy
	gen_proxy_file_for_user
	install_zip_jq && upload_2file

	# Print success message
	echo "All Done and Success by ThienTranJP"

fi
