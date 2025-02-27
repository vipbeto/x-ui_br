#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

#Add some basic function here
function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}
# check root
[[ $EUID -ne 0 ]] && LOGE "Erro: Este script deve ser executado como root!\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    LOGE "Versão do sistema não detectada, entre em contato com o autor do script！\n" && exit 1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        LOGE "Por favor, use o CentOS 7 ou superior！\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        LOGE "Por favor, use o Ubuntu 16 ou posterior！\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        LOGE "Por favor, use o Debian 8 ou superior！\n" && exit 1
    fi
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [padrão$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Se reiniciar o painel, reiniciar o painel também reiniciará o raio-x" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Pressione enter para retornar ao menu principal: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/TelksBr/x-ui_br/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    confirm "Esta função forçará a reinstalação da versão mais recente e os dados não serão perdidos. Deseja continuar?" "n"
    if [[ $? != 0 ]]; then
        LOGE "Cancelado"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/TelksBr/x-ui_br/main/install.sh)
    if [[ $? == 0 ]]; then
        LOGI "A atualização está concluída, o painel foi reiniciado automaticamente "
        exit 0
    fi
}

uninstall() {
    confirm "Tem certeza de que deseja desinstalar o painel, o xray também será desinstalado?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop x-ui
    systemctl disable x-ui
    rm /etc/systemd/system/x-ui.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/x-ui/ -rf
    rm /usr/local/x-ui/ -rf

    echo ""
    echo -e "A desinstalação foi bem-sucedida, se você deseja excluir este script, execute ${green}rm /usr/bin/x-ui -f${plain} após sair do script para excluir"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

reset_user() {
    confirm "Tem certeza de que deseja redefinir o nome de usuário e a senha para admin" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -username admin -password admin
    echo -e "O nome de usuário e a senha foram redefinidos para ${green}admin${plain}, reinicie o painel agora"
    confirm_restart
}

reset_config() {
    confirm "Tem certeza de que deseja redefinir todas as configurações do painel, os dados da conta não serão perdidos, o nome de usuário e a senha não serão alterados" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -reset
    echo -e "Todas as configurações do painel foram redefinidas para o padrão, agora reinicie o painel e use a porta padrão ${green}54321${plain} para acessar o painel"
    confirm_restart
}

check_config() {
    info=$(/usr/local/x-ui/x-ui setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "get current settings error,please check logs"
        show_menu
    fi
    LOGI "${info}"
}

set_port() {
    echo && echo -n -e "Digite o número da porta[1-65535]: " && read port
    if [[ -z "${port}" ]]; then
        LOGD "Cancelado"
        before_show_menu
    else
        /usr/local/x-ui/x-ui setting -port ${port}
        echo -e "Depois de definir a porta, reinicie o painel e use a porta recém-definida ${green}${port}${plain} painel de acesso"
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        LOGI "O painel já está em execução, não há necessidade de reiniciar, se você quiser reiniciar, selecione reiniciar"
    else
        systemctl start x-ui
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "x-ui: Iniciado com sucesso"
        else
            LOGE "O painel falhou ao iniciar, talvez porque o tempo de inicialização excedeu dois segundos, verifique as informações de log mais tarde"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "O painel parou, não há necessidade de parar novamente"
    else
        systemctl stop x-ui
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "x-ui e xray: Desligado com sucesso"
        else
            LOGE "O painel falhou ao parar, talvez porque o tempo de parada tenha excedido dois segundos, verifique as informações de log mais tarde"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart x-ui
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        LOGI "x-ui e xray reiniciados com sucesso"
    else
        LOGE "O painel falhou ao reiniciar, talvez porque o tempo de inicialização tenha excedido dois segundos, verifique as informações de log mais tarde"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status x-ui -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable x-ui
    if [[ $? == 0 ]]; then
        LOGI "x-ui define a inicialização para iniciar com sucesso"
    else
        LOGE "x-ui falhou ao definir a inicialização automática na inicialização"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable x-ui
    if [[ $? == 0 ]]; then
        LOGI "x-ui cancela a inicialização automática com sucesso"
    else
        LOGE "x-ui falhou ao cancelar a inicialização automática de inicialização"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u x-ui.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

migrate_v2_ui() {
    /usr/local/x-ui/x-ui v2-ui

    before_show_menu
}

install_bbr() {
    # temporary workaround for installing bbr
    bash <(curl -L -s https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
    echo ""
    before_show_menu
}

update_shell() {
    wget -O /usr/bin/x-ui -N --no-check-certificate https://raw.githubusercontent.com/TelksBr/x-ui_br/main/x-ui.sh
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "Falha ao baixar o script, verifique se a máquina pode se conectar ao Github"
        before_show_menu
    else
        chmod +x /usr/bin/x-ui
        LOGI "O script de atualização foi bem-sucedido, execute novamente o script" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/x-ui.service ]]; then
        return 2
    fi
    temp=$(systemctl status x-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled x-ui)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        LOGE "O painel já está instalado, não o instale novamente"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        LOGE "Por favor, instale o painel primeiro"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
    0)
        echo -e "Status do painel: ${green} executou ${plain}"
        show_enable_status
        ;;
    1)
        echo -e "status do painel: ${yellow}não está funcionando${plain}"
        show_enable_status
        ;;
    2)
        echo -e "status do painel: ${red}Não instalado${plain}"
        ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "Se deve iniciar automaticamente: ${green}sim${plain}"
    else
        echo -e "Se deve iniciar automaticamente: ${red}nao${plain}"
    fi
}

check_xray_status() {
    count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "Estado do xray: ${green}ativado${plain}"
    else
        echo -e "Estado do xray: ${red}desativado${plain}"
    fi
}

ssl_cert_issue() {
    local method=""
    echo -E ""
    LOGD "********Instruções********"
    LOGI "Este script do shell usará o ACME para emitir certificados SSL."
    LOGI "Aqui, fornecemos dois métodos para a emissão de certificados:"
    LOGI "Método 1: modo ACME Standalone; Precisa manter a porta: 80 aberto (recomendado)"
    LOGI "Método 2: Modo API ACME DNS; Precisa ter a chave da API Global CloudFlare (se o 1º método falhar)"
    LOGI "Certificados são instalados no diretorio /root/cert/"
    read -p "Escolha qual método você deseja (tipo 1 ou 2)": method
    LOGI "Você escolheu o método:${method}"

    if [ "${method}" == "1" ]; then
        ssl_cert_issue_standalone
    elif [ "${method}" == "2" ]; then
        ssl_cert_issue_by_cloudflare
    else
        LOGE "Entrada invalida, repita novamente..."
        exit 1
    fi
}

install_acme() {
    cd ~
    LOGI "Instalando ACME..."
    curl https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        LOGE "Instalação do ACME falhou!"
        return 1
    else
        LOGI "Instalação do ACME concluida"
    fi
    return 0
}

#metodo para o acme standalone
ssl_cert_issue_standalone() {
    #instalando acme primeiro..
    install_acme
    if [ $? -ne 0 ]; then
        LOGE "Instalação do ACME falhou, cheque os logs"
        exit 1
    fi
    #install socat second
    if [[ x"${release}" == x"centos" ]]; then
        yum install socat -y
    else
        apt install socat -y
    fi
    if [ $? -ne 0 ]; then
        LOGE "Instalação do socat falhou, cheque os logs"
        exit 1
    else
        LOGI "Socat instalado com sucesso..."
    fi
    #creando direitorio para o certificado
    certPath=/root/cert
    if [ ! -d "$certPath" ]; then
        mkdir $certPath
    else
        rm -rf $certPath
        mkdir $certPath
    fi
    #obtendo nome de dominio e verificando ele
    local domain=""
    read -p "Por favor, digite seu DOMINIO:" domain
    LOGD "Seu dominio é:${domain},cheque ele..."
    #Aqui precisamos julgar se já existe certificado
    local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')
    if [ ${currentCert} == ${domain} ]; then
        local certInfo=$(~/.acme.sh/acme.sh --list)
        LOGE "O sistema já possui o certificado, não é possivel obter novamente, detalhes do certificado atual:"
        LOGI "$certInfo"
        exit 1
    else
        LOGI "Seu domínio está pronto para a emissão de certificado agora ..."
    fi
    #obtenha a porta necessaria aqui
    local WebPort=80
    read -p "Escolha qual porta você usa, o padrão será porta 80:" WebPort
    if [[ ${WebPort} -gt 65535 || ${WebPort} -lt 1 ]]; then
        LOGE "Sua entrada ${WebPort} é invalida, é use a porta padrão."
    fi
    LOGI "Usando a porta:${WebPort} para obter o certificado, pfv garanta que a porta esteja aberta..."
    #NOTE:isso deve ser tratado pelo usuario
    #abra a porta e mate o processo ocupando
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d ${domain} --standalone --httpport ${WebPort}
    if [ $? -ne 0 ]; then
        LOGE "A obtenção do certificado falhou, cheque os logs"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGE "Certificado obtido com sucesso! Instalando certificado agora..."
    fi
    #instalando certificado
    ~/.acme.sh/acme.sh --installcert -d ${domain} --ca-file /root/cert/ca.cer \
        --cert-file /root/cert/${domain}.cer --key-file /root/cert/${domain}.key \
        --fullchain-file /root/cert/fullchain.cer

    if [ $? -ne 0 ]; then
        LOGE "Instalação do certificado falhou, saindo.."
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGI "Instalação do certificado foi concluida com sucesso! habilitando renovação automatica..."
    fi
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        LOGE "Renovação automatica do SSL falhou. Detalhes do certificado:"
        ls -lah cert
        chmod 755 $certPath
        exit 1
    else
        LOGI "Renovação automatica ativada com sucesso! Detalhes do certificado:"
        ls -lah cert
        chmod 755 $certPath
    fi

}

#method for DNS API mode
ssl_cert_issue_by_cloudflare() {
    echo -E ""
    LOGD "******Requerimentos******"
    LOGI "1.Saber o e-mail associado a cloudflare"
    LOGI "2.Saber a Cloudflare Global API Key"
    LOGI "3.Seu dominio usar Cloudflare como DNS"
    confirm "Você confirma que tem tudo o necessario? [y/n]" "y"
    if [ $? -eq 0 ]; then
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "Instalação do ACME falhou. Cheque os logs"
            exit 1
        fi
        CF_Domain=""
        CF_GlobalKey=""
        CF_AccountEmail=""
        certPath=/root/cert
        if [ ! -d "$certPath" ]; then
            mkdir $certPath
        else
            rm -rf $certPath
            mkdir $certPath
        fi
        LOGD "Insira seu dominio (example.com):"
        read -p "Coloque seu dominio aqui:" CF_Domain
        LOGD "Seu dominio é:${CF_Domain}, cheque isso..."
        #Aqui precisamos julgar se já existe certificado
        local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')
        if [ ${currentCert} == ${CF_Domain} ]; then
            local certInfo=$(~/.acme.sh/acme.sh --list)
            LOGE "O sistema já possui o certificado, não é possivel obter novamente, detalhes do certificado atual:"
            LOGI "$certInfo"
            exit 1
        else
            LOGI "Seu dominio está pronto para obter o certificado..."
        fi
        LOGD "Insira sua Cloudflare Global API key:"
        read -p "Insira a Key aqui:" CF_GlobalKey
        LOGD "Sua cloudflare global API key é:${CF_GlobalKey}"
        LOGD "Coloque seu E-mail Cloudflare:"
        read -p "Insira o e-mail aqui:" CF_AccountEmail
        LOGD "Seu e-mail da cloudflare é:${CF_AccountEmail}"
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [ $? -ne 0 ]; then
            LOGE "Mudança do CA padrão para Lets'Encrypt falhou. Saindo"
            exit 1
        fi
        export CF_Key="${CF_GlobalKey}"
        export CF_Email=${CF_AccountEmail}
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log
        if [ $? -ne 0 ]; then
            LOGE "Obtenção do certificado falhou. Saindo"
            rm -rf ~/.acme.sh/${CF_Domain}
            exit 1
        else
            LOGI "Obtenção do certificado concluida! Instalando..."
        fi
        ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} --ca-file /root/cert/ca.cer \
            --cert-file /root/cert/${CF_Domain}.cer --key-file /root/cert/${CF_Domain}.key \
            --fullchain-file /root/cert/fullchain.cer
        if [ $? -ne 0 ]; then
            LOGE "Instalação do certificado falhou. Saindo"
            rm -rf ~/.acme.sh/${CF_Domain}
            exit 1
        else
            LOGI "Instalação do certificado concluida! Habilitando a renovação automatica..."
        fi
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        if [ $? -ne 0 ]; then
            LOGE "Ativação da renovação falhou. Saindo"
            ls -lah cert
            chmod 755 $certPath
            exit 1
        else
            LOGI "Renovação automatica habilitada! Detalhes:"
            ls -lah cert
            chmod 755 $certPath
        fi
    else
        show_menu
    fi
}

show_usage() {
    echo "------------------------------------------"
    echo "${green}\\  //  ||   || ||${plain}"
    echo "${green} \\//   ||   || ||${plain}"
    echo "${green} //\\   ||___|| ||${plain}"
    echo "${green}//  \\  |_____| ||${plain}"
    echo "------------------------------------------"
    echo "x-ui Como usar o script de gerenciamento: "
    echo "------------------------------------------"
    echo "x-ui              - Mostrar menu de administração (mais funções)"
    echo "x-ui start        - Inicie o painel x-ui"
    echo "x-ui stop         - parar o painel x-ui"
    echo "x-ui restart      - Reinicie o painel x-ui"
    echo "x-ui status       - Ver o status do x-ui"
    echo "x-ui enable       - Defina o x-ui para iniciar automaticamente"
    echo "x-ui disable      - Cancelar a inicialização do x-ui automaticamente"
    echo "x-ui log          - Exibir logs do x-ui"
    echo "x-ui v2-ui        - Migre os dados da conta v2-ui desta máquina para x-ui"
    echo "x-ui update       - Atualize o painel x-ui"
    echo "x-ui install      - Instale o painel x-ui"
    echo "x-ui uninstall    - Desinstale o painel x-ui"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
------------------------------------------
  ${green}\\  //  ||   || ||${plain}
  ${green} \\//   ||   || ||${plain}
  ${green} //\\   ||___|| ||${plain}
  ${green}//  \\  |_____| ||${plain}
------------------------------------------
  ${green}x-ui Script de gerenciamento de painel${plain}
  ${green}0.${plain} script de saída
————————————————
  ${green}1.${plain} Instalar x-ui
  ${green}2.${plain} renovar x-ui
  ${green}3.${plain} Desinstalar x-ui
————————————————
  ${green}4.${plain} redefinir a senha do nome de usuário
  ${green}5.${plain} redefinir as configurações do painel
  ${green}6.${plain} Configurar portas do painel
  ${green}7.${plain} Exibir as configurações atuais do painel
————————————————
  ${green}8.${plain} comece x-ui
  ${green}9.${plain} Pare x-ui
  ${green}10.${plain} reiniciar x-ui
  ${green}11.${plain} Ver o status do x-ui
  ${green}12.${plain} Ver registros x-ui
————————————————
  ${green}13.${plain} 设置 x-ui 开机自启
  ${green}14.${plain} 取消 x-ui 开机自启
————————————————
  ${green}15.${plain} 一key instalar protocolo de congestinamento tcp bbr (kernel mais recente)
  ${green}16.${plain} 一Chave para solicitar o certificado SSL (aplicativo acme)
 "
    show_status
    echo && read -p "Por favor, insira uma seleção [0-16]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        check_uninstall && install
        ;;
    2)
        check_install && update
        ;;
    3)
        check_install && uninstall
        ;;
    4)
        check_install && reset_user
        ;;
    5)
        check_install && reset_config
        ;;
    6)
        check_install && set_port
        ;;
    7)
        check_install && check_config
        ;;
    8)
        check_install && start
        ;;
    9)
        check_install && stop
        ;;
    10)
        check_install && restart
        ;;
    11)
        check_install && status
        ;;
    12)
        check_install && show_log
        ;;
    13)
        check_install && enable
        ;;
    14)
        check_install && disable
        ;;
    15)
        install_bbr
        ;;
    16)
        ssl_cert_issue
        ;;
    *)
        LOGE "Por favor, digite o número correto [0-16]"
        ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
    "start")
        check_install 0 && start 0
        ;;
    "stop")
        check_install 0 && stop 0
        ;;
    "restart")
        check_install 0 && restart 0
        ;;
    "status")
        check_install 0 && status 0
        ;;
    "enable")
        check_install 0 && enable 0
        ;;
    "disable")
        check_install 0 && disable 0
        ;;
    "log")
        check_install 0 && show_log 0
        ;;
    "v2-ui")
        check_install 0 && migrate_v2_ui 0
        ;;
    "update")
        check_install 0 && update 0
        ;;
    "install")
        check_uninstall 0 && install 0
        ;;
    "uninstall")
        check_install 0 && uninstall 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
