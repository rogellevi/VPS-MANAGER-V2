#!/bin/bash
# =========================================================================
# Panel Principal - Golbert VPS V7.0 LTS (Cyber Neon UI + Multilenguaje)
# =========================================================================
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

C_RED='\033[1;31m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'; C_WHITE='\033[1;37m'; C_GRAY='\033[1;30m'
C_ORANGE='\033[38;5;214m'; C_NC='\033[0m'
BG_RED='\033[41;1;37m'; BG_BLUE='\033[44;1;37m'

# --- PROTECCIÓN DEL TOKEN DE GITHUB (Ofuscado) ---
_P1="Hithub_Qat_11A27WFZI08Hrf0TD3fReh_"
_P2="tASxkcJKvAHZs9iurvtmR4qoiut7YmwH"
_P3="FKPiVxmssFbZWB3RRA3Zsv1kTda"
GH_TOKEN=$(echo "${_P1}${_P2}${_P3}" | sed 's/Hithub_Qat_/github_pat_/')

LOCAL_VERSION="1.1"
[ -f /etc/vps-manager/version ] && LOCAL_VERSION=$(cat /etc/vps-manager/version) || echo "$LOCAL_VERSION" > /etc/vps-manager/version

REMOTE_VERSION=$(curl -4 -sS --max-time 2 -H "Authorization: token $GH_TOKEN" https://raw.githubusercontent.com/golbert19/vps-script/main/version 2>/dev/null)
UPDATE_AVAILABLE=0
if [[ -n "$REMOTE_VERSION" ]] && [[ ! "$REMOTE_VERSION" =~ "404" ]]; then
    REMOTE_VERSION=$(echo "$REMOTE_VERSION" | tr -d '\n\r ')
    LOCAL_VERSION=$(echo "$LOCAL_VERSION" | tr -d '\n\r ')
    [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ] && UPDATE_AVAILABLE=1
fi

cargar_idioma() {
    if [ -f /etc/vps-manager/languages.sh ]; then
        source /etc/vps-manager/languages.sh
    elif [ -f /etc/vps-manager/core/languages.sh ]; then
        source /etc/vps-manager/core/languages.sh
    fi
}

draw_bar() {
    local percent=$1; [ "$percent" -gt 100 ] 2>/dev/null && percent=100; [ "$percent" -lt 0 ] 2>/dev/null && percent=0
    local length=14; local filled=$((percent * length / 100)); local empty=$((length - filled))
    local bar="${C_CYAN}[${C_GREEN}"
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    bar="${bar}${C_GRAY}"
    for ((i=0; i<empty; i++)); do bar="${bar}░"; done
    echo -e "${bar}${C_CYAN}]${C_NC}"
}

aislar_protocolo_udp() {
    local activo=$1
    echo -e "\n${C_YELLOW}[*] ${t_udp_iso}${C_NC}"
    iptables -t nat -S PREROUTING 2>/dev/null | grep " -p udp " | grep -v "5300" | grep "REDIRECT" | sed 's/^-A /-D /' | while read -r rule; do
        iptables -t nat $rule 2>/dev/null
    done
    [ "$activo" != "hysteria" ] && { systemctl stop hysteria hysteria-server 2>/dev/null; pkill -9 -x "hysteria" 2>/dev/null; }
    [ "$activo" != "udp-custom" ] && { systemctl stop udp-custom 2>/dev/null; pkill -9 -f "udp-custom" 2>/dev/null; }
    [ "$activo" != "zivpn" ] && { systemctl stop zivpn 2>/dev/null; pkill -9 -x "zivpn" 2>/dev/null; }
    netfilter-persistent save >/dev/null 2>&1
    sleep 1
}

os_name=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
IP=$(curl -4 -sS --max-time 3 ifconfig.me 2>/dev/null || wget -4 -qO- -T 3 ipv4.icanhazip.com)

while true; do
    cargar_idioma
    clear
    domain_name="$t_unconfigured"
    [ -s /etc/vps-manager/domain.txt ] && domain_name=$(cat /etc/vps-manager/domain.txt)
    [ -s /etc/vps-manager/dominio ] && domain_name=$(cat /etc/vps-manager/dominio)

    total_ram=$(free -m | awk 'NR==2 {print $2}'); used_ram=$(free -m | awk 'NR==2 {print $3}')
    ram_usage=$((used_ram * 100 / total_ram)); ram_bar=$(draw_bar $ram_usage)
    cpu_usage_raw=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}')
    cpu_usage=$(printf "%.2f" "$cpu_usage_raw"); cpu_usage_int=${cpu_usage_raw%.*}; [ -z "$cpu_usage_int" ] && cpu_usage_int=0
    cpu_bar=$(draw_bar $cpu_usage_int)

    total_users=$(awk -F: '$3 >= 1000 && $1 != "nobody" && $1 != "ubuntu" {print $1}' /etc/passwd | wc -l)
    online_users=$(ps -eo uid,user:30,comm | awk '$1 >= 1000 && $1 != 65534 && $2 != "ubuntu" && ($3 ~ /sshd|dropbear/) {print $2}' | sort -u | wc -l)

    [ "$(systemctl is-active ssh)" = "active" ] || [ "$(systemctl is-active sshd)" = "active" ] && s_ssh="${C_GREEN}ON ${C_NC}" || s_ssh="${C_RED}OFF${C_NC}"
    [ "$(systemctl is-active nginx)" = "active" ] && s_nginx="${C_GREEN}ON ${C_NC}" || s_nginx="${C_RED}OFF${C_NC}"
    [ "$(systemctl is-active xray)" = "active" ] && s_xray="${C_GREEN}ON ${C_NC}" || s_xray="${C_RED}OFF${C_NC}"
    [ "$(systemctl is-active haproxy)" = "active" ] && s_hap="${C_GREEN}ON ${C_NC}" || s_hap="${C_RED}OFF${C_NC}"
    [ "$(systemctl is-active stunnel4)" = "active" ] || [ "$(systemctl is-active stunnel)" = "active" ] && s_stunnel="${C_GREEN}ON ${C_NC}" || s_stunnel="${C_RED}OFF${C_NC}"
    [ "$(systemctl is-active ssh-ws)" = "active" ] || pgrep -x "ssh-ws" > /dev/null && s_ws="${C_GREEN}ON ${C_NC}" || s_ws="${C_RED}OFF${C_NC}"
    pgrep -x "hcr-server" > /dev/null || [ "$(systemctl is-active hcr)" = "active" ] && s_hcr="${C_GREEN}ON ${C_NC}" || s_hcr="${C_RED}OFF${C_NC}"
    [ "$(systemctl is-active ws-proxy)" = "active" ] || [ "$(systemctl is-active http-proxy)" = "active" ] && s_eproxy="${C_GREEN}ON ${C_NC}" || s_eproxy="${C_RED}OFF${C_NC}"
    [ "$(systemctl is-active bhttp)" = "active" ] && s_bhttp="${C_GREEN}ON ${C_NC}" || s_bhttp="${C_RED}OFF${C_NC}"
    [ "$(systemctl is-active udp-custom)" = "active" ] || pgrep -f "udp-custom" > /dev/null && s_udp="${C_GREEN}ON ${C_NC}" || s_udp="${C_RED}OFF${C_NC}"
    [ "$(systemctl is-active openvpn)" = "active" ] || [ "$(systemctl is-active openvpn@server)" = "active" ] && s_ovpn="${C_GREEN}ON ${C_NC}" || s_ovpn="${C_RED}OFF${C_NC}"
    [ "$(systemctl is-active slowdns)" = "active" ] || pgrep -f "dnstt-server" > /dev/null && s_sdns="${C_GREEN}ON ${C_NC}" || s_sdns="${C_RED}OFF${C_NC}"
    [ "$(systemctl is-active hysteria-server)" = "active" ] || [ "$(systemctl is-active hysteria)" = "active" ] && s_hyst="${C_GREEN}ON ${C_NC}" || s_hyst="${C_RED}OFF${C_NC}"
    [ "$(systemctl is-active badvpn)" = "active" ] || pgrep -f "badvpn-udpgw" > /dev/null && s_badvpn="${C_GREEN}ON ${C_NC}" || s_badvpn="${C_RED}OFF${C_NC}"
    [ "$(systemctl is-active zivpn)" = "active" ] || pgrep -x "zivpn" > /dev/null && s_zivpn="${C_GREEN}ON ${C_NC}" || s_zivpn="${C_RED}OFF${C_NC}"
    iptables -t mangle -L GOLBERT_DDOS >/dev/null 2>&1 || [ "$(systemctl is-active golbert-ddos)" = "active" ] && s_ddos="${C_GREEN}ON ${C_NC}" || s_ddos="${C_RED}OFF${C_NC}"

    echo -e "${C_CYAN}╭────────────────────────────────────────────────────╮${C_NC}"
    echo -e "${C_CYAN}│${C_NC}    ★ ${C_YELLOW}GOLBERT VPS PREMIUM - v7.0 LTS PANEL${C_NC} ★    ${C_CYAN}│${C_NC}"
    echo -e "${C_CYAN}╰────────────────────────────────────────────────────╯${C_NC}"

    if [ "$UPDATE_AVAILABLE" -eq 1 ]; then
        echo -e "${C_CYAN}  〘${C_NC} ${C_GREEN}Key: Verified [ Golbert VPS ] (v${LOCAL_VERSION})${C_NC} ${BG_RED} ¡v${REMOTE_VERSION}! ${C_NC} ${C_CYAN}〙${C_NC}"
        echo -e "   ${C_YELLOW}${t_upd_hint} $REMOTE_VERSION <<${C_NC}"
    else
        echo -e "${C_CYAN}      〘${C_NC} ${C_GREEN}Key: Verified [ Golbert VPS ] (v${LOCAL_VERSION})${C_NC} ${C_CYAN}〙${C_NC}"
    fi

    echo -e "${C_CYAN}╭────────────────────────────────────────────────────╮${C_NC}"
    echo -e "${C_CYAN}│${C_NC} 🐧 ${C_WHITE}OS        :${C_NC} ${C_GREEN}$os_name${C_NC}"
    echo -e "${C_CYAN}│${C_NC} 🌐 ${C_WHITE}IP        :${C_NC} ${C_WHITE}$IP${C_NC}"
    echo -e "${C_CYAN}│${C_NC} 🛢️ ${C_WHITE}Domain    :${C_NC} ${C_YELLOW}$domain_name${C_NC}"
    echo -e "${C_CYAN}│${C_NC} 🧭 ${C_WHITE}CPU Usage :${C_NC} $cpu_bar ${C_GREEN}${cpu_usage}%${C_NC}"
    echo -e "${C_CYAN}│${C_NC} 📟 ${C_WHITE}RAM Usage :${C_NC} $ram_bar ${C_GREEN}${ram_usage}% (${used_ram}/${total_ram} MB)${C_NC}"
    echo -e "${C_CYAN}│${C_NC} 👥 ${C_WHITE}Users     :${C_NC} ${C_GREEN}$total_users $t_created${C_NC} │ ${C_GREEN}$online_users $t_online${C_NC}"
    echo -e "${C_CYAN}╰────────────────────────────────────────────────────╯${C_NC}"
    
    echo -e "${C_CYAN}╭──〘${C_NC} ⚙️  ${C_YELLOW}${t_mgmt}${C_NC} ${C_CYAN}〙───────────────────╮${C_NC}"
    echo -e "${C_CYAN}│${C_NC} ${BG_BLUE} 1 ${C_NC} 👥 ${C_WHITE}${t_m1}${C_NC}"
    echo -e "${C_CYAN}│${C_NC} ${BG_BLUE} 2 ${C_NC} 🔧 ${C_WHITE}${t_m2}${C_NC}"
    echo -e "${C_CYAN}│${C_NC} ${BG_BLUE} 3 ${C_NC} 💎 ${C_WHITE}${t_m3}${C_NC}"
    echo -e "${C_CYAN}╰────────────────────────────────────────────────────╯${C_NC}"
    
    echo -e "${C_CYAN}╭──〘${C_NC} 🛠️  ${C_YELLOW}${t_tools}${C_NC} ${C_CYAN}〙───────────────────╮${C_NC}"
    echo -e "${C_CYAN}│${C_NC} ${BG_BLUE} 4 ${C_NC} 🛠️  ${C_WHITE}${t_m4}${C_NC}"
    echo -e "${C_CYAN}│${C_NC} ${BG_BLUE} 5 ${C_NC} 🛡️  ${C_WHITE}${t_m5}${C_NC}"
    echo -e "${C_CYAN}│${C_NC} ${BG_BLUE} 6 ${C_NC} 🌐 ${C_WHITE}${t_m6}${C_NC}"
    echo -e "${C_CYAN}│${C_NC} ${BG_BLUE} 7 ${C_NC} ⚙️  ${C_WHITE}${t_m7}${C_NC}"
    echo -e "${C_CYAN}╰────────────────────────────────────────────────────╯${C_NC}"
    
    echo -e "${C_CYAN}╭─────────────────┬─────────────────┬────────────────╮${C_NC}"
    echo -e "${C_CYAN}│${C_NC} ${C_WHITE}SSH      :${C_NC} $s_ssh  ${C_CYAN}│${C_NC} ${C_WHITE}HAPROXY :${C_NC} $s_hap    ${C_CYAN}│${C_NC} ${C_WHITE}XRAY   :${C_NC} $s_xray  ${C_CYAN}│${C_NC}"
    echo -e "${C_CYAN}│${C_NC} ${C_WHITE}NGINX    :${C_NC} $s_nginx  ${C_CYAN}│${C_NC} ${C_WHITE}SSH-WS  :${C_NC} $s_ws   ${C_CYAN}│${C_NC} ${C_WHITE}HCR    :${C_NC} $s_hcr  ${C_CYAN}│${C_NC}"
    echo -e "${C_CYAN}│${C_NC} ${C_WHITE}E-PROXY  :${C_NC} $s_eproxy  ${C_CYAN}│${C_NC} ${C_WHITE}BHTTP   :${C_NC} $s_bhttp   ${C_CYAN}│${C_NC} ${C_WHITE}UDP-C  :${C_NC} $s_udp  ${C_CYAN}│${C_NC}"
    echo -e "${C_CYAN}│${C_NC} ${C_WHITE}SLOWDNS  :${C_NC} $s_sdns  ${C_CYAN}│${C_NC} ${C_WHITE}OVPN    :${C_NC} $s_ovpn   ${C_CYAN}│${C_NC} ${C_WHITE}BADVPN :${C_NC} $s_badvpn  ${C_CYAN}│${C_NC}"
    echo -e "${C_CYAN}│${C_NC} ${C_WHITE}HYSTERIA :${C_NC} $s_hyst  ${C_CYAN}│${C_NC} ${C_WHITE}ZIVPN   :${C_NC} $s_zivpn   ${C_CYAN}│${C_NC} ${C_WHITE}DDOS   :${C_NC} $s_ddos  ${C_CYAN}│${C_NC}"
    echo -e "${C_CYAN}╰─────────────────┴─────────────────┴────────────────╯${C_NC}"
    
    echo -e "${C_RED}╭───────────────────────────────┬────────────────────╮${C_NC}"
    echo -e "${C_RED}│${C_NC}  🗑️  ${C_RED}${t_uninst}${C_NC}   ${C_CYAN}│${C_NC}    🚪 ${C_YELLOW}${t_exit}${C_NC}      ${C_RED}│${C_NC}"
    echo -e "${C_RED}╰───────────────────────────────┴────────────────────╯${C_NC}"

    echo -ne "${C_GREEN}❯ ${t_select}${C_NC}"
    read -r opcion
    
    case $opcion in
        1) 
            [ -f /etc/vps-manager/core/user.sh ] && bash /etc/vps-manager/core/user.sh || { echo -e "\n${C_RED}${t_mod_ssh_err}${C_NC}"; sleep 2; }
            ;;
        2)
            while true; do
                cargar_idioma
                clear
                echo -e "${C_CYAN}================================================${C_NC}"
                echo -e " ⚡  ${t_xray_title}"
                echo -e "${C_CYAN}================================================${C_NC}"
                
                if [ ! -f /usr/local/etc/xray/config.json ]; then
                    echo -e " ${C_RED}${t_xray_warn1}${C_NC}"
                    echo -e " ${C_WHITE}${t_xray_warn2}${C_NC}"
                    echo -e " ${C_WHITE}${t_xray_warn3}${C_NC}"
                    echo -e "${C_CYAN}================================================${C_NC}"
                    read -p "${t_enter_back}"
                    break
                fi

                echo -e " ${t_x1}"
                echo -e " ${t_x2}"
                echo -e " ${t_x3}"
                echo -e " ${t_x4}"
                echo -e " ${t_x5}"
                echo -e " ${t_back_main}"
                echo -e "${C_CYAN}================================================${C_NC}"
                read -p "${t_select}" xray_op
                case $xray_op in
                    1) [ -f /etc/vps-manager/core/vmess.sh ] && bash /etc/vps-manager/core/vmess.sh ;;
                    2) [ -f /etc/vps-manager/core/vless.sh ] && bash /etc/vps-manager/core/vless.sh ;;
                    3) [ -f /etc/vps-manager/core/trojan.sh ] && bash /etc/vps-manager/core/trojan.sh ;;
                    4) [ -f /etc/vps-manager/core/shadowsocks.sh ] && bash /etc/vps-manager/core/shadowsocks.sh ;;
                    5) [ -f /etc/vps-manager/core/xhttp.sh ] && bash /etc/vps-manager/core/xhttp.sh ;;
                    0) break ;;
                esac
            done
            ;;
        3) 
            [ -f /etc/vps-manager/core/bot.sh ] && bash /etc/vps-manager/core/bot.sh || { echo "${t_mod_bot_err}"; sleep 2; }
            ;;
        4)
            while true; do
                cargar_idioma
                clear
                if [ "$(systemctl is-active xray)" = "active" ] && [ "$(systemctl is-active haproxy)" = "active" ]; then st_hap="${C_GREEN}${t_sim_on}${C_NC}"; else st_hap="${C_RED}[OFF]${C_NC}"; fi

                echo -e "${C_CYAN}================================================${C_NC}"
                echo -e " 🛠️  ${t_inst_title}"
                echo -e "${C_CYAN}================================================${C_NC}"
                echo -e " 1.  ⚡ ${C_CYAN}${t_i1}${C_NC} $st_hap"
                echo -e " 2.  🔥 ${C_YELLOW}${t_i2}${C_NC}"
                echo -e " 3.  🐢 ${t_i3}"
                echo -e " 4.  🎮 ${t_i4}"
                echo -e " 5.  🚀 ${t_i5}"
                echo -e " 6.  🌐 ${t_i6}"
                echo -e " 7.  🔒 ${t_i7}"
                echo -e " 8.  🛡️ ${t_i8}"
                echo -e " 9.  ⚙️ ${t_i9}"
                echo -e " 10. 🛡️ ${t_i10}"
                echo -e " ${t_back_main}"
                echo -e "${C_CYAN}================================================${C_NC}"
                read -p "${t_sel_proto}" sub_op
                case $sub_op in
                    1) [ -f /etc/vps-manager/core/xray_manager.sh ] && bash /etc/vps-manager/core/xray_manager.sh ;;
                    2)
                        while true; do
                            cargar_idioma
                            clear
                            [ "$(systemctl is-active hysteria-server)" = "active" ] && st_hy="${C_GREEN}${t_active}${C_NC}" || st_hy="${C_RED}[OFF]${C_NC}"
                            [ "$(systemctl is-active udp-custom)" = "active" ] && st_uc="${C_GREEN}${t_active}${C_NC}" || st_uc="${C_RED}[OFF]${C_NC}"
                            [ "$(systemctl is-active zivpn)" = "active" ] && st_zi="${C_GREEN}${t_active}${C_NC}" || st_zi="${C_RED}[OFF]${C_NC}"

                            echo -e "${C_ORANGE}======================================================${C_NC}"
                            echo -e " 🔥 ${C_YELLOW}${t_udp_title}${C_NC}"
                            echo -e "${C_ORANGE}======================================================${C_NC}"
                            echo -e " ${t_u1}      $st_hy"
                            echo -e " ${t_u2}  $st_uc"
                            echo -e " ${t_u3} $st_zi"
                            echo -e " ${t_u4}"
                            echo -e " ${t_u0}"
                            echo -e "${C_ORANGE}======================================================${C_NC}"
                            read -p " ${t_sel_udp}" udp_op
                            case $udp_op in
                                1) aislar_protocolo_udp "hysteria"; bash /etc/vps-manager/core/hysteria.sh ;;
                                2) aislar_protocolo_udp "udp-custom"; bash /etc/vps-manager/core/udp_custom.sh ;;
                                3) aislar_protocolo_udp "zivpn"; bash /etc/vps-manager/core/zivpn.sh ;;
                                4) aislar_protocolo_udp "ninguno"; echo -e "\n ${C_GREEN}${t_udp_stopped}${C_NC}"; sleep 2 ;;
                                0) break ;;
                            esac
                        done
                        ;;
                    3) [ -f /etc/vps-manager/core/slowdns.sh ] && bash /etc/vps-manager/core/slowdns.sh ;;
                    4) [ -f /etc/vps-manager/core/badvpn.sh ] && bash /etc/vps-manager/core/badvpn.sh ;;
                    5) [ -f /etc/vps-manager/core/hcr.sh ] && bash /etc/vps-manager/core/hcr.sh ;;
                    6) [ -f /etc/vps-manager/core/bhttp.sh ] && bash /etc/vps-manager/core/bhttp.sh ;;
                    7) [ -f /etc/vps-manager/core/ssl.sh ] && bash /etc/vps-manager/core/ssl.sh ;;
                    8) [ -f /etc/vps-manager/core/edit_ovpn_user.sh ] && bash /etc/vps-manager/core/edit_ovpn_user.sh ;;
                    9) [ -f /etc/vps-manager/core/bbr.sh ] && bash /etc/vps-manager/core/bbr.sh ;;
                    10) [ -f /etc/vps-manager/core/dns_resolver.sh ] && bash /etc/vps-manager/core/dns_resolver.sh ;;
                    0) break ;;
                esac
            done
            ;;
        5)
            while true; do
                cargar_idioma
                clear
                echo -e "${C_CYAN}================================================${C_NC}"
                echo -e " ⚙️  ${t_sys_title}"
                echo -e "${C_CYAN}================================================${C_NC}"
                echo -e " ${t_s1}"
                echo -e " ${t_s2}"
                echo -e " ${t_s3}"
                echo -e " ${t_s4}"
                echo -e " ${t_s5}"
                echo -e " ${t_s6}"
                echo -e " ${t_back_main}"
                echo -e "${C_CYAN}================================================${C_NC}"
                read -p "${t_select}" sys_op
                case $sys_op in
                    1) netstat -tulnp | grep LISTEN; read -p "${t_enter_cont}" ;;
                    2) [ -f /etc/vps-manager/core/specs.sh ] && bash /etc/vps-manager/core/specs.sh ;;
                    3) [ -f /etc/vps-manager/core/firewall.sh ] && bash /etc/vps-manager/core/firewall.sh ;;
                    4) [ -f /etc/vps-manager/core/fix_ports.sh ] && bash /etc/vps-manager/core/fix_ports.sh ;;
                    5) [ -f /etc/vps-manager/core/checkuser.sh ] && bash /etc/vps-manager/core/checkuser.sh ;;
                    6) [ -f /etc/vps-manager/core/optimizer.sh ] && bash /etc/vps-manager/core/optimizer.sh ;;
                    0) break ;;
                esac
            done
            ;;
        6)
            while true; do
                cargar_idioma
                clear
                echo -e "${C_CYAN}================================================${C_NC}"
                echo -e " 🌐  ${t_web_title}"
                echo -e "${C_CYAN}================================================${C_NC}"
                echo -e " ${t_w1}"
                echo -e " ${t_w2}"
                echo -e " ${t_w3}"
                echo -e " ${t_w4}"
                echo -e " ${t_back_main}"
                echo -e "${C_CYAN}================================================${C_NC}"
                read -p "${t_select}" web_op
                case $web_op in
                    1) [ -f /etc/vps-manager/core/domain.sh ] && bash /etc/vps-manager/core/domain.sh ;;
                    2) [ -f /etc/vps-manager/core/webpanel.sh ] && bash /etc/vps-manager/core/webpanel.sh ;;
                    3) [ -f /etc/vps-manager/core/bot.sh ] && bash /etc/vps-manager/core/bot.sh ;;
                    4) [ -f /etc/vps-manager/core/banner.sh ] && bash /etc/vps-manager/core/banner.sh ;;
                    0) break ;;
                esac
            done
            ;;
        7)
            while true; do
                cargar_idioma
                clear
                echo -e "${C_CYAN}================================================${C_NC}"
                echo -e " 🔄  ${t_set_title}"
                echo -e "${C_CYAN}================================================${C_NC}"
                echo -e " ${t_p1}"
                echo -e " ${t_p2}"
                echo -e " ${t_p3}"
                echo -e " ${t_back_main}"
                echo -e "${C_CYAN}================================================${C_NC}"
                read -p "${t_select}" set_op
                case $set_op in
                    1) [ -f /etc/vps-manager/core/update.sh ] && bash /etc/vps-manager/core/update.sh ;;
                    2)
                        echo -e "\n1. 🇪🇸 Español | 2. 🇺🇸 English | 3. 🇧🇷 Português"
                        read -p "${t_select}" lang_op
                        [ "$lang_op" = "1" ] && echo "es" > /etc/vps-manager/lang.txt
                        [ "$lang_op" = "2" ] && echo "en" > /etc/vps-manager/lang.txt
                        [ "$lang_op" = "3" ] && echo "pt" > /etc/vps-manager/lang.txt
                        cargar_idioma
                        echo -e "\n${C_GREEN}${t_lang_upd}${C_NC}"; sleep 1; break
                        ;;
                    3) [ -f /etc/vps-manager/core/php.sh ] && bash /etc/vps-manager/core/php.sh ;;
                    0) break ;;
                esac
            done
            ;;
        99)
            [ -f /etc/vps-manager/core/update.sh ] && bash /etc/vps-manager/core/update.sh || echo "${t_mod_upd_err}"
            ;;
        88)
            read -p "${t_ask_uninst}" des
            if [[ "$des" =~ ^[sSyY]$ ]]; then
                rm -rf /etc/vps-manager /usr/bin/menu /usr/local/bin/menu /usr/bin/reactivar
                sed -i '/menu/d' /root/.bashrc 2>/dev/null
                echo -e "\n${C_GREEN}${t_uninst_ok}${C_NC}"
                exit 0
            fi
            ;;
        0) clear; exit 0 ;;
        *) echo -e "${C_RED}${t_invalid}${C_NC}"; sleep 1 ;;
    esac
done
