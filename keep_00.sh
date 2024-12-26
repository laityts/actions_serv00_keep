#!/bin/bash

SCRIPT_PATH="$(pwd)/$(basename "$0")"                 # 脚本路径
LOG="$(pwd)/$(basename "$0" .sh).log"

export CFIP=${CFIP:-'www.visa.com.tw'}         # 优选域名或优选ip
export CFPORT=${CFIPPORT:-'443'}               # 优选域名或优选ip对应端口
export UUID=${UUID:-'f8805ffb-d0a7-4f3b-8ffc-5aa99fc963c8'}

TOKEN=$TOKEN
CHAT_ID=$CHAT_ID

if [ -f "$LOG" ]; then
    echo "$LOG 日志存在，正在删除..."
    rm "$LOG"
    echo "$LOG 日志已删除。"
else
    echo "$LOG 日志不存在，无需删除。"
fi 
 
 # serv00或ct8服务器及端口配置, argo固定隧道可不填写
declare -A servers=(  # 账号:密码:tcp端口:udp1端口:udp2端口:argo域名:Argo隧道json或token 
    ["s14.serv00.com"]="$SERVER_1"
)

declare -A servers2=(  # 账号:密码:tcp端口:udp1端口:udp2端口:argo域名:Argo隧道json或token 
    ["s14.serv00.com"]="$SERVER_2"
)

declare -A servers3=(  # 账号:密码:tcp端口:udp1端口:udp2端口:argo域名:Argo隧道json或token 
    ["s14.serv00.com"]="$SERVER_3"
    ["s14.serv00.com"]="$SERVER_4"
)

# 定义颜色
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }

export TERM=xterm
export DEBIAN_FRONTEND=noninteractive
install_packages() {
    if [ -f /etc/debian_version ]; then
        package_manager="apt-get install -y"
    elif [ -f /etc/redhat-release ]; then
        package_manager="yum install -y"
    elif [ -f /etc/fedora-release ]; then
        package_manager="dnf install -y"
    elif [ -f /etc/alpine-release ]; then
        package_manager="apk add"
    else
        red "不支持的系统架构！"
        exit 1
    fi
    $package_manager sshpass curl netcat-openbsd jq cron >/dev/null 2>&1 &
}
install_packages
clear

# 检查 TCP 端口是否通畅
check_tcp_port() {
    local host=$1
    local port=$2
    nc -z -w 3 "$host" "$port" &> /dev/null
    return $?
}

# 检查 Argo 隧道是否在线
check_argo_tunnel() {
    local domain=$1
    if [ -z "$domain" ]; then
        return 1
    else
        http_code=$(curl -o /dev/null -s -w "%{http_code}\n" "https://$domain")
        if [ "$http_code" -eq 404 ]; then
            return 0
        else
            return 1
        fi
    fi
}

# 执行远程命令
run_remote_command() {
    local host=$1
    local ssh_user=$2
    local ssh_pass=$3
    local tcp_port=$4
    local udp1_port=$5
    local udp2_port=$6
    local argo_domain=${7}
    local argo_auth=${8}

    remote_command="VMESS_PORT=$tcp_port HY2_PORT=$udp1_port TUIC_PORT=$udp2_port ARGO_DOMAIN=$argo_domain ARGO_AUTH='$argo_auth' CFIP=$CFIP CFPORT=$CFPORT UUID=$UUID bash <(curl -Ls https://raw.githubusercontent.com/eooce/sing-box/main/sb_00.sh)"
    
    sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no "$ssh_user@$host" "$remote_command"
}

# 循环遍历服务器列表检测
for host in "${!servers[@]}"; do
    IFS=':' read -r ssh_user ssh_pass tcp_port udp1_port udp2_port argo_domain argo_auth <<< "${servers[$host]}"

    tcp_attempt=0
    argo_attempt=0
    max_attempts=3
    time=$(TZ="Asia/Hong_Kong" date +"%Y-%m-%d %H:%M")

    # 检查 TCP 端口
    while [ $tcp_attempt -lt $max_attempts ]; do
        if check_tcp_port "$host" "$tcp_port"; then
            green "$time  TCP端口${tcp_port}通畅 服务器: $host  账户: $ssh_user"
            tcp_attempt=0
            break
        else
            red "$time  TCP端口${tcp_port}不通 服务器: $host  账户: $ssh_user"
            sleep 10
            tcp_attempt=$((tcp_attempt+1))
        fi
    done

    # 检查 Argo 隧道
    while [ $argo_attempt -lt $max_attempts ]; do
        if check_argo_tunnel "$argo_domain"; then
            green "$time  Argo 隧道在线 Argo域名: $argo_domain   账户: $ssh_user\n"
            curl -s -X POST https://api.telegram.org/bot$TOKEN/sendMessage -d chat_id=$CHAT_ID -d text="$time  Argo 隧道在线 Argo域名: $argo_domain   账户: $ssh_user"
            argo_attempt=0
            break
        else
            red "$time  Argo 隧道离线 Argo域名: $argo_domain   账户: $ssh_user"
            curl -s -X POST https://api.telegram.org/bot$TOKEN/sendMessage -d chat_id=$CHAT_ID -d text="$time  Argo 隧道离线 Argo域名: $argo_domain   账户: $ssh_user"
            sleep 10
            argo_attempt=$((argo_attempt+1))
        fi
    done
   
    # 如果3次检测失败，则执行 SSH 连接并执行远程命令
    if [ $tcp_attempt -ge 3 ] || [ $argo_attempt -ge 3 ] ; then
        yellow "$time 多次检测失败，尝试通过SSH连接并远程执行命令  服务器: $host  账户: $ssh_user"
        if sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no "$ssh_user@$host" -q exit; then
            echo "$time  SSH远程连接成功 服务器: $host  账户 : $ssh_user  密码 : $ssh_pass"
            echo "$time  UUID : $UUID"
            echo "$time  VMPORT: $tcp_port  H2PORT : $udp1_port  TUICPO : $udp2_port"
            echo "$time  ARGO_DOMAIN : $argo_domain  ARGO_AUTH : $argo_auth"
            output=$(run_remote_command "$host" "$ssh_user" "$ssh_pass" "$tcp_port" "$udp1_port" "$udp2_port" "$argo_domain" "$argo_auth")
            yellow "远程命令执行结果：\n"
            echo "$output"
            curl -s -X POST https://api.telegram.org/bot$TOKEN/sendMessage -d chat_id=$CHAT_ID -d text="$output"
        else
            red "$time  连接失败，请检查你的账户密码 服务器: $host  账户: $ssh_user"
            curl -s -X POST https://api.telegram.org/bot$TOKEN/sendMessage -d chat_id=$CHAT_ID -d text="$time  连接失败，请检查你的账户密码 服务器: $host  账户: $ssh_user"
        fi
    fi
done

# 循环遍历服务器列表检测
for host in "${!servers2[@]}"; do
    IFS=':' read -r ssh_user ssh_pass tcp_port udp1_port udp2_port argo_domain argo_auth <<< "${servers2[$host]}"

    tcp_attempt=0
    argo_attempt=0
    max_attempts=3
    time=$(TZ="Asia/Hong_Kong" date +"%Y-%m-%d %H:%M")

    # 检查 TCP 端口
    while [ $tcp_attempt -lt $max_attempts ]; do
        if check_tcp_port "$host" "$tcp_port"; then
            green "$time  TCP端口${tcp_port}通畅 服务器: $host  账户: $ssh_user"
            tcp_attempt=0
            break
        else
            red "$time  TCP端口${tcp_port}不通 服务器: $host  账户: $ssh_user"
            sleep 10
            tcp_attempt=$((tcp_attempt+1))
        fi
    done

    # 检查 Argo 隧道
    while [ $argo_attempt -lt $max_attempts ]; do
        if check_argo_tunnel "$argo_domain"; then
            green "$time  Argo 隧道在线 Argo域名: $argo_domain   账户: $ssh_user\n"
            curl -s -X POST https://api.telegram.org/bot$TOKEN/sendMessage -d chat_id=$CHAT_ID -d text="$time  Argo 隧道在线 Argo域名: $argo_domain   账户: $ssh_user"
            argo_attempt=0
            break
        else
            red "$time  Argo 隧道离线 Argo域名: $argo_domain   账户: $ssh_user"
            curl -s -X POST https://api.telegram.org/bot$TOKEN/sendMessage -d chat_id=$CHAT_ID -d text="$time  Argo 隧道离线 Argo域名: $argo_domain   账户: $ssh_user"
            sleep 10
            argo_attempt=$((argo_attempt+1))
        fi
    done
   
    # 如果3次检测失败，则执行 SSH 连接并执行远程命令
    if [ $tcp_attempt -ge 3 ] || [ $argo_attempt -ge 3 ] ; then
        yellow "$time 多次检测失败，尝试通过SSH连接并远程执行命令  服务器: $host  账户: $ssh_user"
        if sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no "$ssh_user@$host" -q exit; then
            echo "$time  SSH远程连接成功 服务器: $host  账户 : $ssh_user  密码 : $ssh_pass"
            echo "$time  UUID : $UUID"
            echo "$time  VMPORT: $tcp_port  H2PORT : $udp1_port  TUICPO : $udp2_port"
            echo "$time  ARGO_DOMAIN : $argo_domain  ARGO_AUTH : $argo_auth"
            output=$(run_remote_command "$host" "$ssh_user" "$ssh_pass" "$tcp_port" "$udp1_port" "$udp2_port" "$argo_domain" "$argo_auth")
            yellow "远程命令执行结果：\n"
            echo "$output"
            curl -s -X POST https://api.telegram.org/bot$TOKEN/sendMessage -d chat_id=$CHAT_ID -d text="$output"
        else
            red "$time  连接失败，请检查你的账户密码 服务器: $host  账户: $ssh_user"
            curl -s -X POST https://api.telegram.org/bot$TOKEN/sendMessage -d chat_id=$CHAT_ID -d text="$time  连接失败，请检查你的账户密码 服务器: $host  账户: $ssh_user"
        fi
    fi
done

# 循环遍历服务器列表检测
for host in "${!servers3[@]}"; do
    IFS=':' read -r ssh_user ssh_pass tcp_port udp1_port udp2_port argo_domain argo_auth <<< "${servers3[$host]}"

    tcp_attempt=0
    argo_attempt=0
    max_attempts=3
    time=$(TZ="Asia/Hong_Kong" date +"%Y-%m-%d %H:%M")

    # 检查 TCP 端口
    while [ $tcp_attempt -lt $max_attempts ]; do
        if check_tcp_port "$host" "$tcp_port"; then
            green "$time  TCP端口${tcp_port}通畅 服务器: $host  账户: $ssh_user"
            tcp_attempt=0
            break
        else
            red "$time  TCP端口${tcp_port}不通 服务器: $host  账户: $ssh_user"
            sleep 10
            tcp_attempt=$((tcp_attempt+1))
        fi
    done

    # 检查 Argo 隧道
    while [ $argo_attempt -lt $max_attempts ]; do
        if check_argo_tunnel "$argo_domain"; then
            green "$time  Argo 隧道在线 Argo域名: $argo_domain   账户: $ssh_user\n"
            curl -s -X POST https://api.telegram.org/bot$TOKEN/sendMessage -d chat_id=$CHAT_ID -d text="$time  Argo 隧道在线 Argo域名: $argo_domain   账户: $ssh_user"
            argo_attempt=0
            break
        else
            red "$time  Argo 隧道离线 Argo域名: $argo_domain   账户: $ssh_user"
            curl -s -X POST https://api.telegram.org/bot$TOKEN/sendMessage -d chat_id=$CHAT_ID -d text="$time  Argo 隧道离线 Argo域名: $argo_domain   账户: $ssh_user"
            sleep 10
            argo_attempt=$((argo_attempt+1))
        fi
    done
   
    # 如果3次检测失败，则执行 SSH 连接并执行远程命令
    if [ $tcp_attempt -ge 3 ] || [ $argo_attempt -ge 3 ] ; then
        yellow "$time 多次检测失败，尝试通过SSH连接并远程执行命令  服务器: $host  账户: $ssh_user"
        if sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no "$ssh_user@$host" -q exit; then
            echo "$time  SSH远程连接成功 服务器: $host  账户 : $ssh_user  密码 : $ssh_pass"
            echo "$time  UUID : $UUID"
            echo "$time  VMPORT: $tcp_port  H2PORT : $udp1_port  TUICPO : $udp2_port"
            echo "$time  ARGO_DOMAIN : $argo_domain  ARGO_AUTH : $argo_auth"
            output=$(run_remote_command "$host" "$ssh_user" "$ssh_pass" "$tcp_port" "$udp1_port" "$udp2_port" "$argo_domain" "$argo_auth")
            yellow "远程命令执行结果：\n"
            echo "$output"
            curl -s -X POST https://api.telegram.org/bot$TOKEN/sendMessage -d chat_id=$CHAT_ID -d text="$output"
        else
            red "$time  连接失败，请检查你的账户密码 服务器: $host  账户: $ssh_user"
            curl -s -X POST https://api.telegram.org/bot$TOKEN/sendMessage -d chat_id=$CHAT_ID -d text="$time  连接失败，请检查你的账户密码 服务器: $host  账户: $ssh_user"
        fi
    fi
done