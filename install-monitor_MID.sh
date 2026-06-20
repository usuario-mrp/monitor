#!/bin/sh

# CONFIGURACION
GITHUB_TOKEN="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"

URL_BINARIO="https://api.github.com/repos/bmanzano/resource_tmp/contents/v1/validator_arm"
URL_YAML="https://api.github.com/repos/bmanzano/resource_tmp/contents/v1/config.yaml"
URL_YAML_SIGNAL="https://api.github.com/repos/bmanzano/resource_tmp/contents/v1/config-signal.yaml"

DIR_INSTALACION="/root/monitor"
DIR_ARCHIVO_YAML="/root/monitor/configs"
NOMBRE_SERVICIO="monitor-health"
USUARIO_EJECUCION="root"
DESCRIPCION="Servicio para monitoreo del estado del validador"
BINARY_NAME="validator_arm"

# CONSTANTES
SERVICE_FILE="/etc/init.d/$NOMBRE_SERVICIO"
BINARY_PATH="$DIR_INSTALACION/$BINARY_NAME"
CONFIG_PATH="$DIR_ARCHIVO_YAML/config.yaml"
CONFIG_PATH_SIGNAL="$DIR_ARCHIVO_YAML/config-signal.yaml"
LOG_FILE="/var/log/$NOMBRE_SERVICIO.log"
PID_FILE="/var/run/$NOMBRE_SERVICIO.pid"

# FUNCIONES
log_info() { echo "[INFO] $1"; }
log_success() { echo "[OK] $1"; }
log_warning() { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; }

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Este script debe ejecutarse como root"
        exit 1
    fi
}

is_installed() {
    if [ -f "$SERVICE_FILE" ] && [ -f "$BINARY_PATH" ]; then
        return 0
    else
        return 1
    fi
}
download_file() {
    local url="$1"
    local output="$2"
    local description="$3"
    
    log_info "Descargando $description..."
    
    if command -v curl >/dev/null 2>&1; then
        http_code=$(curl -s -L \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3.raw" \
            -o "$output" \
            -w "%{http_code}" \
            "$url")
        
        log_info "Codigo HTTP: $http_code"
        
        if [ "$http_code" = "200" ] && [ -f "$output" ] && [ -s "$output" ]; then
            # Verificar error JSON de GitHub
            if head -c 50 "$output" | grep -q '"message"'; then
                log_error "GitHub devolvio un error"
                return 1
            fi
            
            # Deteccion automatica del tipo de archivo
            file_info=$(file "$output" 2>/dev/null || echo "unknown")
            
            if echo "$file_info" | grep -q "ELF.*executable"; then
                log_success "Binario ejecutable descargado ($(wc -c < "$output") bytes)"
            elif echo "$file_info" | grep -q "text"; then
                log_success "Archivo de texto descargado ($(wc -c < "$output") bytes)"
            else
                log_success "Archivo descargado ($(wc -c < "$output") bytes) - Tipo: $file_info"
            fi
            return 0
        else
            log_error "Error HTTP: $http_code o archivo vacio"
            return 1
        fi
    else
        log_error "Se necesita curl"
        return 1
    fi
}

create_service_file() {
    log_info "Creando archivo de servicio..."
    
    cat > "$SERVICE_FILE" << 'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          monitor-health
# Required-Start:    $network $local_fs $remote_fs
# Required-Stop:     $network $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Servicio para monitoreo del estado del validador
# Description:       Servicio para monitoreo del estado del validador
### END INIT INFO

NAME="monitor-health"
DESC="Servicio para monitoreo del estado del validador"
DAEMON="/root/monitor/validator_arm"
PIDFILE="/var/run/monitor-health.pid"
LOGFILE="/var/log/monitor-health.log"
USER="root"
WORKDIR="/root/monitor"

case "$1" in
    start)
        echo "Iniciando $DESC: $NAME"
        start-stop-daemon --start --background \
            --make-pidfile \
            --pidfile $PIDFILE \
            --chuid $USER \
            --chdir $WORKDIR \
            --exec $DAEMON
        ;;
    stop)
        echo "Deteniendo $DESC: $NAME"
        start-stop-daemon --stop --pidfile $PIDFILE
        rm -f $PIDFILE
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    status)
        if [ -f $PIDFILE ] && kill -0 $(cat $PIDFILE) 2>/dev/null; then
            echo "$DESC esta ejecutandose (PID: $(cat $PIDFILE))"
        else
            echo "$DESC no esta ejecutandose"
        fi
        ;;
    *)
        echo "Uso: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
EOF

    chmod +x "$SERVICE_FILE"
    log_success "Archivo de servicio creado: $SERVICE_FILE"
}

install_service() {
    log_info "Iniciando instalacion de $NOMBRE_SERVICIO..."
    check_root
    
    # Crear directorios
    log_info "Creando directorios..."
    mkdir -p "$DIR_INSTALACION" "$DIR_ARCHIVO_YAML"
    
    # Descargar binario
    if download_file "$URL_BINARIO" "$BINARY_PATH" "binario"; then
        chmod +x "$BINARY_PATH"
        log_success "Binario instalado: $BINARY_PATH"
    else
        log_error "No se pudo descargar el binario"
        exit 1
    fi
    
    # Descargar configuracion de Signal
    if download_file "$URL_YAML_SIGNAL" "$CONFIG_PATH_SIGNAL" "configuracion YAML de Signal"; then
        log_success "Configuracion YAML de Signal descargada"
    else
        log_error "No se pudo descargar YAML de Signal y no se puede continuar con la instalacion"
        exit 1
    fi

    # Descargar configuracion principal
    if download_file "$URL_YAML" "$CONFIG_PATH" "configuracion YAML"; then
        log_success "Configuracion YAML descargada"
    else
        log_error "No se pudo descargar YAML principal y no se puede continuar con la instalacion"
        exit 1
    fi
    
    # Crear servicio
    create_service_file
    
    # Debugging: Check if the service file exists before configuring automatic startup
    if [ ! -f "$SERVICE_FILE" ]; then
        log_error "El archivo de servicio no fue creado: $SERVICE_FILE"
        exit 1
    fi

    # Configurar inicio automatico
    log_info "Configurando inicio automatico..."
    if update-rc.d "$NOMBRE_SERVICIO" defaults; then
        log_success "Inicio automatico configurado"
    else
        log_error "Error configurando inicio automatico"
        exit 1
    fi
    
    # Crear archivo de log
    touch "$LOG_FILE"
    chown "$USUARIO_EJECUCION":"$USUARIO_EJECUCION" "$LOG_FILE"
    
    # Iniciar servicio
    log_info "Iniciando servicio..."
    if service "$NOMBRE_SERVICIO" start; then
        log_success "Servicio iniciado"
    else
        log_error "Error iniciando servicio"
    fi
    
    sleep 2
    
    # Verificar instalacion
    if service "$NOMBRE_SERVICIO" status >/dev/null 2>&1; then
        log_success "INSTALACION COMPLETADA - Servicio ejecutandose"
    else
        log_warning "INSTALACION COMPLETADA pero servicio no iniciado automaticamente"
    fi
    
    show_instructions
}

update_service() {
    UPDATE_ALL="$1"
    log_info "Actualizando $NOMBRE_SERVICIO..."
    
    if ! is_installed; then
        log_error "El servicio no esta instalado. Use --install primero."
        exit 1
    fi
    
    # Detener servicio
    service "$NOMBRE_SERVICIO" stop
    
    # Descargar nuevo binario
    if download_file "$URL_BINARIO" "$BINARY_PATH.new" "nuevo binario"; then
        chmod +x "$BINARY_PATH.new"
        mv "$BINARY_PATH.new" "$BINARY_PATH"
        log_success "Binario actualizado"
    else
        log_error "No se pudo actualizar el binario"
        service "$NOMBRE_SERVICIO" start
        exit 1
    fi
    
    # Si la variable es "all", también actualiza las configuraciones
    if [ "$UPDATE_ALL" = "all" ]; then
        # Actualizar configuracion principal
        if download_file "$URL_YAML" "$CONFIG_PATH.new" "nueva configuracion"; then
            mv "$CONFIG_PATH.new" "$CONFIG_PATH"
            log_success "Configuracion principal actualizada"
        else
            rm -f "$CONFIG_PATH.new"
            log_warning "No se pudo actualizar la configuracion principal"
        fi

        # Actualizar configuracion de Signal
        if download_file "$URL_YAML_SIGNAL" "$CONFIG_PATH_SIGNAL.new" "nueva configuracion de Signal"; then
            mv "$CONFIG_PATH_SIGNAL.new" "$CONFIG_PATH_SIGNAL"
            log_success "Configuracion de Signal actualizada"
        else
            rm -f "$CONFIG_PATH_SIGNAL.new"
            log_warning "No se pudo actualizar la configuracion de Signal"
        fi
    fi
    
    # Reiniciar servicio
    service "$NOMBRE_SERVICIO" start
    log_success "Servicio actualizado correctamente"
}

uninstall_service() {
    log_warning "Desinstalando $NOMBRE_SERVICIO..."
    
    if ! is_installed; then
        log_error "El servicio no esta instalado."
        exit 1
    fi
    
    # Detener servicio
    service "$NOMBRE_SERVICIO" stop
    
    # Remover servicio
    update-rc.d -f "$NOMBRE_SERVICIO" remove
    rm -f "$SERVICE_FILE"
    
    # Remover archivos
    rm -f "$PID_FILE"
    rm -f "$LOG_FILE"
    
    echo "¿Desea eliminar los directorios de datos ($DIR_INSTALACION)? [y/N]: "
    read respuesta
    if [ "$respuesta" = "y" ] || [ "$respuesta" = "Y" ]; then
        rm -rf "$DIR_INSTALACION"
        log_success "Directorios de datos eliminados"
    else
        log_info "Directorios de datos conservados en $DIR_INSTALACION"
    fi
    
    log_success "Servicio desinstalado completamente"
}

show_status() {
    if is_installed; then
        log_success "Servicio instalado"
        echo "Binario: $BINARY_PATH"
        echo "Configuracion: $CONFIG_PATH"
        echo "Logs: $LOG_FILE"
        
        if service "$NOMBRE_SERVICIO" status >/dev/null 2>&1; then
            log_success "Estado: EJECUTANDOSE"
        else
            log_error "Estado: DETENIDO"
        fi
    else
        log_error "Servicio no instalado"
    fi
}

show_instructions() {
    echo
    log_success "INSTALACION COMPLETADA"
    echo "=========================================="
    echo "Comandos de gestion:"
    echo "  service $NOMBRE_SERVICIO start"
    echo "  service $NOMBRE_SERVICIO stop" 
    echo "  service $NOMBRE_SERVICIO restart"
    echo "  service $NOMBRE_SERVICIO status"
    echo
    echo "Ver logs:"
    echo "  tail -f $LOG_FILE"
    echo
    echo "Configuracion:"
    echo "  $CONFIG_PATH"
    echo
    echo "Actualizar:"
    echo "  $0 --update"
    echo
    echo "Actualizar con configuración:"
    echo "  $0 --update all"
    echo
    echo "Desinstalar:"
    echo "  $0 --uninstall"
    echo "=========================================="
}

show_usage() {
    echo "Uso: $0 [OPCION]"
    echo
    echo "Opciones:"
    echo "  --install     Instalar el servicio"
    echo "  --update      Actualizar el servicio"
    echo "  --update all  Actualizar el servicio con configuraciones"
    echo "  --uninstall   Desinstalar el servicio"
    echo "  --status      Mostrar estado del servicio"
    echo "  --help        Mostrar esta ayuda"
    echo
    echo "Ejemplos:"
    echo "  $0 --install    # Instalar servicio"
    echo "  $0 --status     # Ver estado"
}

# MENU PRINCIPAL
case "$1" in
    --install)
        install_service
        ;;
    --update)
        update_service "$2"
        ;;
    --uninstall)
        uninstall_service
        ;;
    --status)
        show_status
        ;;
    --help|"")
        show_usage
        ;;
    *)
        log_error "Opcion no valida: $1"
        show_usage
        exit 1
        ;;
esac
