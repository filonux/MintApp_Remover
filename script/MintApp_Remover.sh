#!/bin/bash
#
# MintApp Remover
# Desinstalador de aplicaciones preinstaladas de Linux Mint 22.3 Cinnamon
#
# Copyright (C) 2026 Filonux
#
# Licencia:
#   MintApp Remover es software libre distribuido bajo los términos de la
#   GNU General Public License versión 3 (GPLv3).
#   Consulte el archivo LICENSE para obtener el texto completo de la
#   licencia.
#
# Uso: chmod +x MintApp_Remover.sh && ./MintApp_Remover.sh
#
# Ofrece un catálogo curado de aplicaciones que Linux Mint 22.3 instala por
# defecto (Opción 2) y un modo avanzado (Opción 3) que escanea los lanzadores
# reales del menú (.desktop) para detectar aplicaciones fuera de ese catálogo,
# con exclusión de componentes del sistema y simulación de apt antes de purgar.
#
# Compatibilidad: diseñado y probado para Linux Mint 22.3 Cinnamon. Requiere
# apt/dpkg, por lo que también se ejecuta en Ubuntu y otras distros basadas en
# Debian/Ubuntu, aunque el catálogo de la Opción 2 está curado específicamente
# para Mint y en otras distros probablemente no detecte nada; la Opción 3 es
# la más portable, ya que se basa en un escaneo dinámico de lanzadores en vez
# de una lista fija. No es compatible con distros sin apt/dpkg (Fedora, Arch,
# openSUSE, etc.).

set -uo pipefail

# ----------------------------------------------------------------------------
# Colores del modo texto plano. Paleta restringida a verde/negro/azul; los
# elementos marcados o seleccionados usan bloque sólido (negro sobre color)
# para distinguirse a simple vista del resto.
# ----------------------------------------------------------------------------
readonly C_RESET="\033[0m"
readonly C_TITLE="\033[1;34m"      # azul (cabeceras, títulos)
readonly C_OK="\033[1;32m"         # verde (éxito / detectado)
readonly C_WARN="\033[1;34m"       # azul (avisos)
readonly C_MARK="\033[1;30;42m"    # negro sobre verde (marcado/seleccionado)
readonly C_ERR="\033[1;30;44m"     # negro sobre azul (error)
readonly C_BOLD="\033[1m"

# ----------------------------------------------------------------------------
# Interfaz: whiptail (checkboxes gráficos en terminal) si está disponible,
# si no, se recurre automáticamente al menú de texto plano.
# ----------------------------------------------------------------------------
HAVE_WHIPTAIL=0
if command -v whiptail >/dev/null 2>&1; then
    HAVE_WHIPTAIL=1
fi
readonly HAVE_WHIPTAIL

# ----------------------------------------------------------------------------
# Paleta de colores de whiptail: se sobrescribe la paleta por defecto (que
# suele resaltar en rojo/magenta) por una propia limitada a verde/negro/azul.
# Fondo negro con texto verde en elementos normales, azul en bordes/títulos,
# y negro sobre verde sólido en cualquier elemento activo o marcado.
# ----------------------------------------------------------------------------
export NEWT_COLORS='
root=green,black
border=blue,black
window=green,black
shadow=black,black
title=blue,black
button=black,blue
actbutton=black,green
compactbutton=blue,black
checkbox=green,black
actcheckbox=black,green
entry=green,black
label=green,black
listbox=green,black
actlistbox=black,green
sellistbox=black,blue
actsellistbox=black,green
textbox=green,black
acttextbox=black,green
helpline=blue,black
roottext=blue,black
emptyscale=,black
fullscale=,green
disentry=blue,black
'

readonly WT_TITLE="MintApp Remover - Linux Mint 22.3"

# Dimensiones de los cuadros whiptail: se recalculan en cada pantalla según
# el tamaño real de la terminal (ver calcular_dimensiones_whiptail), ya que
# pedir a whiptail una caja mayor que la terminal deja botones fuera del
# área interactiva. Los valores de aquí son solo de emergencia por si alguna
# función se llamase antes de la primera llamada a esa función.
WT_HEIGHT=20
WT_WIDTH=74
WT_LISTHEIGHT=10
WT_HEIGHT_BIG=22
WT_WIDTH_BIG=76

# Calcula el tamaño de los cuadros whiptail a partir del tamaño real de la
# terminal en ese momento. Se llama al inicio de cada pantalla, así que si
# el usuario redimensiona la ventana entre una y otra, la siguiente ya se
# ajusta sola.
calcular_dimensiones_whiptail() {
    local term_lines term_cols
    term_lines=$(tput lines 2>/dev/null)
    term_cols=$(tput cols 2>/dev/null)

    # Sin terminal real detectable, usar un tamaño conservador por defecto.
    case "$term_lines" in ''|*[!0-9]*) term_lines=24 ;; esac
    case "$term_cols"  in ''|*[!0-9]*) term_cols=80 ;; esac
    [ "$term_lines" -lt 10 ] && term_lines=24
    [ "$term_cols" -lt 40 ] && term_cols=80

    # Cuadros "normales" (menú, checklist, confirmaciones cortas).
    WT_HEIGHT=$(( term_lines - 4 ))
    [ "$WT_HEIGHT" -gt 22 ] && WT_HEIGHT=22
    [ "$WT_HEIGHT" -lt 12 ] && WT_HEIGHT=12

    WT_WIDTH=$(( term_cols - 6 ))
    [ "$WT_WIDTH" -gt 78 ] && WT_WIDTH=78
    [ "$WT_WIDTH" -lt 50 ] && WT_WIDTH=50

    # Margen para bordes, prompt, listbox, fila de botones y borde inferior.
    local margen_checklist=10
    WT_LISTHEIGHT=$(( WT_HEIGHT - margen_checklist ))
    if [ "$WT_LISTHEIGHT" -lt 3 ]; then
        WT_LISTHEIGHT=3
        # Si con lista mínima de 3 líneas no cabe el margen, se agranda
        # WT_HEIGHT sin sobrepasar la terminal real.
        local necesario=$(( WT_LISTHEIGHT + margen_checklist ))
        if [ "$necesario" -gt "$WT_HEIGHT" ]; then
            WT_HEIGHT="$necesario"
            [ "$WT_HEIGHT" -gt $((term_lines - 1)) ] && WT_HEIGHT=$((term_lines - 1))
        fi
    fi

    # Cuadros "grandes" (texto largo, como la simulación de apt). Mismo
    # margen de seguridad, aprovechando más espacio si la terminal es
    # grande.
    WT_HEIGHT_BIG=$(( term_lines - 2 ))
    [ "$WT_HEIGHT_BIG" -gt 28 ] && WT_HEIGHT_BIG=28
    [ "$WT_HEIGHT_BIG" -lt 14 ] && WT_HEIGHT_BIG=14

    WT_WIDTH_BIG=$(( term_cols - 4 ))
    [ "$WT_WIDTH_BIG" -gt 90 ] && WT_WIDTH_BIG=90
    [ "$WT_WIDTH_BIG" -lt 60 ] && WT_WIDTH_BIG=60

    # Red de seguridad final: en terminales muy pequeñas los mínimos fijos
    # de arriba podrían dar una altura mayor que la terminal real.
    [ "$WT_HEIGHT" -ge "$term_lines" ] && WT_HEIGHT=$((term_lines - 1))
    [ "$WT_HEIGHT_BIG" -ge "$term_lines" ] && WT_HEIGHT_BIG=$((term_lines - 1))
}

# ----------------------------------------------------------------------------
# Listado interno de aplicaciones candidatas
# Formato: "Nombre visible|paquete1,paquete2|Descripción"
# ----------------------------------------------------------------------------
CATALOG=(
    "Firefox|firefox|Navegador web"
    "Thunderbird|thunderbird|Cliente de correo electrónico"
    "LibreOffice|libreoffice,libreoffice-core,libreoffice-writer,libreoffice-calc,libreoffice-impress,libreoffice-draw,libreoffice-base,libreoffice-math|Suite ofimática"
    "Calculator|gnome-calculator|Calculadora"
    "Calendar|gnome-calendar|Calendario"
    "Document Viewer|xreader|Visor de documentos"
    "Document Scanner|simple-scan|Escanear documentos e imágenes"
    "Web App Manager|webapp-manager|Crear aplicaciones web"
    "Warpinator|warpinator|Compartir archivos en red local"
    "Transmission|transmission-gtk|Cliente BitTorrent"
    "Hypnotix|hypnotix|Cliente IPTV"
    "Rhythmbox|rhythmbox|Reproductor de música"
    "Celluloid|celluloid|Reproductor de vídeo"
    "Pix|pix|Organizador de fotografías"
    "Drawing|drawing|Editor sencillo de imágenes"
    "Image Viewer|xviewer|Visor de imágenes"
    "Text Editor|xed|Editor de texto"
    "Archive Manager|file-roller|Gestor de archivos comprimidos"
    "Sticky Notes|sticky|Notas adhesivas"
    "Character Map|gucharmap|Mapa de caracteres"
    "Backup Tool|mintbackup|Copias de seguridad personales"
    "Herramientas USB (Image Writer + Formatter)|mintstick|Grabar imágenes ISO y formatear memorias USB"
    "Disks|gnome-disk-utility|Gestión de discos y particiones"
    "Disk Usage Analyzer|baobab|Analizador de uso de disco"
    "System Monitor|gnome-system-monitor|Monitor de procesos y recursos"
)
readonly CATALOG

# Arrays que se rellenan tras la detección
DETECTED_NAMES=()
DETECTED_PACKAGES=()
DETECTED_DESC=()
DETECTION_DONE=0

# ----------------------------------------------------------------------------
# Modo avanzado (Opción 3): lista negra de componentes del sistema.
# A diferencia del CATALOG (lista blanca), aquí el universo de partida es
# "todos los lanzadores del menú", por lo que se excluye por patrón lo que
# sea claramente del sistema. Es una capa más, no la única: se complementa
# con la comprobación de Priority/Essential de dpkg y con la simulación real
# de "apt-get -s purge" antes de confirmar.
# ----------------------------------------------------------------------------
EXCLUDED_PATTERNS=(
    "cinnamon*" "muffin*" "cjs*" "xapp*" "nemo*" "mint*"
    "gnome-terminal*" "xfce4-terminal*" "xterm*"
    "gnome-control-center*" "gnome-shell*" "gnome-session*" "gnome-settings-daemon*"
    "gdm3*" "lightdm*" "slick-greeter*"
    "policykit-1*" "polkit*" "gksu*" "pkexec*"
    "synaptic*" "gdebi*" "software-properties*" "apt" "apt-*" "dpkg" "dpkg-*"
    "gufw*" "ufw*" "network-manager*" "nm-*"
    "systemd*" "udisks2*" "gparted*" "blueman*" "timeshift*"
    "pulseaudio*" "pipewire*"
    "cups*" "system-config-printer*" "printer-driver*"
)
readonly EXCLUDED_PATTERNS

# Arrays que se rellenan tras el escaneo de lanzadores (.desktop)
ADV_NAMES=()
ADV_PACKAGES=()
ADV_UNMANAGED_NAMES=()
declare -A SEEN_PKGS=()

# ----------------------------------------------------------------------------
# Utilidades
# ----------------------------------------------------------------------------
pause() {
    echo
    read -rp "Pulsa Enter para continuar..." _
}

header() {
    local titulo="${1:-MintApp Remover - Linux Mint 22.3}"
    clear
    echo -e "${C_TITLE}========================================="
    echo " $titulo"
    echo -e "=========================================${C_RESET}"
    echo
}

# ----------------------------------------------------------------------------
# Pantalla inicial (se muestra una sola vez, antes del menú principal) con
# las instrucciones de manejo. En whiptail el método fiable es flechas + TAB
# + ENTER/ESPACIO (escribir el número no selecciona nada); en el modo texto
# plano sí funciona escribir el número, por ser un menú propio con "read".
# ----------------------------------------------------------------------------
mostrar_instrucciones_navegacion() {
    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        calcular_dimensiones_whiptail
        local texto="CÓMO MOVERSE POR LOS MENÚS\n\n"
        texto+="  ↑ / ↓      Moverse por la lista de opciones.\n"
        texto+="  ESPACIO    Marcar o desmarcar una aplicación (pantallas con casillas).\n"
        texto+="  TAB        Cambiar el foco entre la lista y los botones (Aceptar / Cancelar / Salir).\n"
        texto+="             Algunos botones NO se pueden pulsar sin pasar antes por aquí.\n"
        texto+="  ENTER      Confirmar la opción o el botón que esté resaltado.\n\n"
        texto+="Escribir el número de una opción NO la selecciona: usa siempre las flechas."
        whiptail --title "$WT_TITLE" --scrolltext --ok-button "Entendido" --msgbox "$texto" "$WT_HEIGHT_BIG" "$WT_WIDTH_BIG"
    else
        header "Cómo moverse por los menús"
        echo "Este script se ejecuta en modo texto (whiptail no está disponible):"
        echo
        echo "  - Escribe el NÚMERO de la opción que quieras y pulsa Enter."
        echo "  - En las pantallas de selección múltiple: escribe el número de"
        echo "    una app para marcarla/desmarcarla (se resaltará en verde),"
        echo "    escribe 'c' para confirmar, o '0' para volver atrás."
        pause
    fi
}

# Comprueba si al menos uno de los paquetes de una entrada (separados por
# coma) está realmente instalado. Se exige el estado exacto
# "install ok installed": un paquete desinstalado sin purgar queda en
# "deinstall ok config-files" y "dpkg -s" seguiría devolviendo éxito aunque
# solo queden ficheros de configuración residuales.
package_installed() {
    local pkgs="$1"
    local IFS=','
    local pkg
    for pkg in $pkgs; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "^install ok installed$"; then
            return 0
        fi
    done
    return 1
}

# Dada una entrada "paquete1,paquete2,...", imprime (uno por línea) solo los
# paquetes de esa lista que están realmente instalados, ya que algunas apps
# del catálogo tienen más de un nombre posible según la versión de Mint.
installed_packages_from_list() {
    local pkgs="$1"
    local IFS=','
    local pkg
    for pkg in $pkgs; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "^install ok installed$"; then
            echo "$pkg"
        fi
    done
}

# ----------------------------------------------------------------------------
# Opción 1: Detectar programas
# ----------------------------------------------------------------------------
detectar_programas() {
    DETECTED_NAMES=()
    DETECTED_PACKAGES=()
    DETECTED_DESC=()

    local entry name pkgs desc
    for entry in "${CATALOG[@]}"; do
        IFS='|' read -r name pkgs desc <<< "$entry"
        if package_installed "$pkgs"; then
            DETECTED_NAMES+=("$name")
            DETECTED_PACKAGES+=("$pkgs")
            DETECTED_DESC+=("$desc")
        fi
    done

    DETECTION_DONE=1

    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        calcular_dimensiones_whiptail
        local resumen="Programas detectados:\n\n"
        local i
        for i in "${!DETECTED_NAMES[@]}"; do
            resumen+="  ✓ ${DETECTED_NAMES[$i]}\n"
        done
        resumen+="\n${#DETECTED_NAMES[@]} aplicaciones detectadas."
        whiptail --title "$WT_TITLE" --scrolltext --ok-button "Aceptar" --msgbox "$resumen" "$WT_HEIGHT" "$WT_WIDTH"
    else
        header
        echo -e "${C_BOLD}Programas detectados${C_RESET}"
        echo
        local i
        for i in "${!DETECTED_NAMES[@]}"; do
            echo -e "  ${C_OK}✓${C_RESET} ${DETECTED_NAMES[$i]}"
        done
        echo
        echo "${#DETECTED_NAMES[@]} aplicaciones detectadas."
        pause
    fi
}

# Ejecuta el purge y muestra el resultado, adaptado a la interfaz activa.
ejecutar_purge() {
    local -a pkgs=("$@")

    header
    echo "Ejecutando desinstalación..."
    echo
    sudo DEBIAN_FRONTEND=noninteractive apt purge -y "${pkgs[@]}"
    local status=$?
    echo

    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        calcular_dimensiones_whiptail
        if [ "$status" -eq 0 ]; then
            whiptail --title "$WT_TITLE" --ok-button "Aceptar" --msgbox "Desinstalación completada." "$WT_HEIGHT" "$WT_WIDTH"
        else
            whiptail --title "$WT_TITLE" --ok-button "Aceptar" --msgbox "Hubo un problema durante la desinstalación (código $status).\n\nRevisa el mensaje de apt más arriba en la terminal." "$WT_HEIGHT" "$WT_WIDTH"
        fi
    else
        if [ "$status" -eq 0 ]; then
            echo -e "${C_OK}Desinstalación completada.${C_RESET}"
        else
            echo -e "${C_ERR}Hubo un problema durante la desinstalación (código $status).${C_RESET}"
        fi
        pause
    fi
}

# ----------------------------------------------------------------------------
# Opción 2: Desinstalar programas — versión whiptail (checkboxes)
# ----------------------------------------------------------------------------
desinstalar_programas_whiptail() {
    calcular_dimensiones_whiptail

    local -a checklist_args=()
    local i
    for i in "${!DETECTED_NAMES[@]}"; do
        # tag / item / status(OFF)
        checklist_args+=("$((i+1))" "${DETECTED_NAMES[$i]} — ${DETECTED_DESC[$i]}" "OFF")
    done

    local altura_lista=$(( ${#DETECTED_NAMES[@]} < WT_LISTHEIGHT ? ${#DETECTED_NAMES[@]} : WT_LISTHEIGHT ))

    local seleccion
    seleccion=$(whiptail --title "$WT_TITLE" \
        --ok-button "Aceptar" --cancel-button "Cancelar" \
        --checklist "Seleccione las aplicaciones que desea eliminar.\n(↑ ↓ mover | Espacio: marcar | TAB: ir a Aceptar/Cancelar | Enter: confirmar)" \
        "$WT_HEIGHT" "$WT_WIDTH" "$altura_lista" \
        "${checklist_args[@]}" \
        3>&1 1>&2 2>&3)
    local wt_status=$?

    if [ "$wt_status" -ne 0 ]; then
        # Cancelado por el usuario
        return
    fi

    if [ -z "$seleccion" ]; then
        whiptail --title "$WT_TITLE" --ok-button "Aceptar" --msgbox "No se ha seleccionado ninguna aplicación." "$WT_HEIGHT" "$WT_WIDTH"
        return
    fi

    # $seleccion viene como: "1" "3" "5"  (con comillas). Quitamos las
    # comillas y partimos por espacios, sin usar eval sobre la salida de
    # whiptail.
    local -a to_remove_names=()
    local -a to_remove_pkgs=()
    local -a tags
    local tag idx pkg
    read -ra tags <<< "${seleccion//\"/}"
    for tag in "${tags[@]}"; do
        idx=$((tag-1))
        to_remove_names+=("${DETECTED_NAMES[$idx]}")
        while IFS= read -r pkg; do
            to_remove_pkgs+=("$pkg")
        done < <(installed_packages_from_list "${DETECTED_PACKAGES[$idx]}")
    done

    if [ "${#to_remove_pkgs[@]}" -eq 0 ]; then
        whiptail --title "$WT_TITLE" --ok-button "Aceptar" --msgbox "Las aplicaciones seleccionadas ya no están instaladas." "$WT_HEIGHT" "$WT_WIDTH"
        return
    fi

    local resumen="Se eliminarán:\n\n"
    local name
    for name in "${to_remove_names[@]}"; do
        resumen+="  ✓ $name\n"
    done

    if ! whiptail --title "$WT_TITLE" --scrolltext --yes-button "Sí, eliminar" --no-button "Cancelar" --yesno "$resumen" "$WT_HEIGHT" "$WT_WIDTH"; then
        return
    fi

    ejecutar_purge "${to_remove_pkgs[@]}"
    DETECTION_DONE=0
}

# ----------------------------------------------------------------------------
# Opción 2: Desinstalar programas — versión texto plano (fallback)
# ----------------------------------------------------------------------------
desinstalar_programas_texto() {
    local -a selected
    local i
    for i in "${!DETECTED_NAMES[@]}"; do
        selected[i]=0
    done

    while true; do
        header
        echo "Seleccione las aplicaciones que desea eliminar"
        echo "(escriba el número para marcar/desmarcar, 'c' para confirmar, '0' para volver)"
        echo

        for i in "${!DETECTED_NAMES[@]}"; do
            local num
            num=$(printf '%2d' "$((i+1))")
            if [ "${selected[$i]}" -eq 1 ]; then
                # Marcada: línea completa en bloque negro-sobre-verde, para
                # que se distinga a simple vista de las no marcadas.
                echo -e "  ${num}) ${C_MARK} ☑ ${DETECTED_NAMES[$i]} ${C_RESET}"
            else
                echo "  ${num}) ☐ ${DETECTED_NAMES[$i]}"
            fi
            printf "        %s\n" "${DETECTED_DESC[$i]}"
        done

        echo
        local choice
        read -rp "> " choice

        case "$choice" in
            0)
                return
                ;;
            c|C)
                break
                ;;
            ''|*[!0-9]*)
                echo -e "${C_ERR}Opción no válida.${C_RESET}"
                sleep 1
                ;;
            *)
                # 10#$choice fuerza base 10: sin esto, Bash interpreta un
                # cero a la izquierda ("010", "018"...) como octal.
                local idx=$((10#$choice - 1))
                if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#DETECTED_NAMES[@]}" ]; then
                    if [ "${selected[$idx]}" -eq 1 ]; then
                        selected[idx]=0
                    else
                        selected[idx]=1
                    fi
                else
                    echo -e "${C_ERR}Número fuera de rango.${C_RESET}"
                    sleep 1
                fi
                ;;
        esac
    done

    local -a to_remove_names=()
    local -a to_remove_pkgs=()
    local pkg
    for i in "${!DETECTED_NAMES[@]}"; do
        if [ "${selected[$i]}" -eq 1 ]; then
            to_remove_names+=("${DETECTED_NAMES[$i]}")
            while IFS= read -r pkg; do
                to_remove_pkgs+=("$pkg")
            done < <(installed_packages_from_list "${DETECTED_PACKAGES[$i]}")
        fi
    done

    if [ "${#to_remove_names[@]}" -eq 0 ]; then
        header
        echo "No se ha seleccionado ninguna aplicación."
        pause
        return
    fi

    if [ "${#to_remove_pkgs[@]}" -eq 0 ]; then
        header
        echo "Las aplicaciones seleccionadas ya no están instaladas."
        pause
        return
    fi

    header
    echo "Se eliminarán:"
    echo
    local name
    for name in "${to_remove_names[@]}"; do
        echo -e "  ${C_WARN}✓${C_RESET} $name"
    done
    echo
    local confirm
    read -rp "¿Desea continuar? [s/N]: " confirm

    if [[ ! "$confirm" =~ ^[sS]$ ]]; then
        echo "Operación cancelada."
        pause
        return
    fi

    ejecutar_purge "${to_remove_pkgs[@]}"
    DETECTION_DONE=0
}

# ----------------------------------------------------------------------------
# Opción 2: Desinstalar programas — despachador
# ----------------------------------------------------------------------------
desinstalar_programas() {
    if [ "$DETECTION_DONE" -eq 0 ]; then
        detectar_programas
    fi

    if [ "${#DETECTED_NAMES[@]}" -eq 0 ]; then
        if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
            whiptail --title "$WT_TITLE" --msgbox "No se ha detectado ninguna aplicación candidata instalada." "$WT_HEIGHT" "$WT_WIDTH"
        else
            header
            echo "No se ha detectado ninguna aplicación candidata instalada."
            pause
        fi
        return
    fi

    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        desinstalar_programas_whiptail
    else
        desinstalar_programas_texto
    fi
}

# ----------------------------------------------------------------------------
# Opción 3: Buscar otras aplicaciones (MODO AVANZADO)
# En vez de depender de nombres de paquete fijos, recorre los lanzadores
# reales del menú (.desktop) y deduce el paquete dueño de cada uno con
# "dpkg -S". Al partir de un universo más amplio y menos controlado que el
# catálogo curado, filtra por lista negra y SIEMPRE muestra antes una
# simulación real ("apt-get -s purge") con el plan completo, incluyendo
# cualquier dependiente que apt decida arrastrar.
# ----------------------------------------------------------------------------

# Devuelve 0 (true) si el paquete debe excluirse del modo avanzado, ya sea
# porque coincide con un patrón de la lista negra o porque dpkg lo marca
# como Essential o de prioridad required/important (componentes del sistema).
paquete_excluido() {
    local pkg="$1"
    local pattern

    for pattern in "${EXCLUDED_PATTERNS[@]}"; do
        # shellcheck disable=SC2053
        if [[ "$pkg" == $pattern ]]; then
            return 0
        fi
    done

    local priority
    priority=$(dpkg-query -W -f='${Priority}' "$pkg" 2>/dev/null)
    case "$priority" in
        required|important)
            return 0
            ;;
    esac

    local essential
    essential=$(dpkg-query -W -f='${Essential}' "$pkg" 2>/dev/null)
    if [ "$essential" = "yes" ]; then
        return 0
    fi

    return 1
}

# Devuelve 0 (true) si el paquete ya está contemplado en el CATALOG curado,
# para no ofrecerlo dos veces (una vez por la Opción 2 y otra por la 3).
paquete_en_catalogo() {
    local pkg="$1"
    local entry pkgs p

    for entry in "${CATALOG[@]}"; do
        IFS='|' read -r _ pkgs _ <<< "$entry"
        for p in ${pkgs//,/ }; do
            if [ "$p" = "$pkg" ]; then
                return 0
            fi
        done
    done
    return 1
}

# Procesa un único fichero .desktop: filtra por Type/NoDisplay/Hidden,
# resuelve su paquete dueño con dpkg -S y, si pasa todos los filtros, lo
# añade a los arrays ADV_*. Si no tiene paquete dueño (Flatpak, Snap o
# instalación manual) o el dueño es ambiguo, se registra como "no
# gestionable" en vez de intentar purgarlo.
procesar_desktop_file() {
    local f="$1"
    local tipo_entrada nodisplay hidden name owner_line pkg

    tipo_entrada=$(grep -m1 '^Type=' "$f" 2>/dev/null | cut -d= -f2-)
    [ "$tipo_entrada" = "Application" ] || return

    nodisplay=$(grep -m1 '^NoDisplay=' "$f" 2>/dev/null | cut -d= -f2-)
    [ "$nodisplay" = "true" ] && return

    hidden=$(grep -m1 '^Hidden=' "$f" 2>/dev/null | cut -d= -f2-)
    [ "$hidden" = "true" ] && return

    name=$(grep -m1 '^Name=' "$f" 2>/dev/null | cut -d= -f2-)
    [ -n "$name" ] || name=$(basename "$f" .desktop)

    owner_line=$(dpkg -S "$f" 2>/dev/null | head -n1)
    if [ -z "$owner_line" ]; then
        ADV_UNMANAGED_NAMES+=("$name")
        return
    fi

    pkg="${owner_line%%:*}"
    if [[ "$pkg" == *","* ]]; then
        # Varios paquetes reclaman el mismo fichero: caso ambiguo, no se
        # ofrece para purgar automáticamente.
        ADV_UNMANAGED_NAMES+=("$name (paquete ambiguo)")
        return
    fi
    read -r pkg <<< "$pkg"

    [ -n "${SEEN_PKGS[$pkg]:-}" ] && return
    paquete_excluido "$pkg" && return
    paquete_en_catalogo "$pkg" && return

    SEEN_PKGS[$pkg]=1
    ADV_NAMES+=("$name")
    ADV_PACKAGES+=("$pkg")
}

# Ordena alfabéticamente (por nombre visible) los arrays ADV_* tras el
# escaneo, para que la lista sea más fácil de revisar.
ordenar_arrays_avanzado() {
    [ "${#ADV_NAMES[@]}" -eq 0 ] && return

    local i combined
    combined=""
    for i in "${!ADV_NAMES[@]}"; do
        combined+="${ADV_NAMES[$i]}"$'\x01'"${ADV_PACKAGES[$i]}"$'\n'
    done

    ADV_NAMES=()
    ADV_PACKAGES=()

    local name pkg
    while IFS=$'\x01' read -r name pkg; do
        [ -z "$name" ] && continue
        ADV_NAMES+=("$name")
        ADV_PACKAGES+=("$pkg")
    done < <(printf '%s' "$combined" | sort -f -t $'\x01' -k1,1)
}

# Recorre los directorios estándar de lanzadores y rellena los arrays
# ADV_NAMES / ADV_PACKAGES / ADV_UNMANAGED_NAMES.
escanear_lanzadores_detectar() {
    ADV_NAMES=()
    ADV_PACKAGES=()
    ADV_UNMANAGED_NAMES=()
    SEEN_PKGS=()

    local -a dirs=(
        "/usr/share/applications"
        "/usr/local/share/applications"
        "/var/lib/snapd/desktop/applications"
        "/var/lib/flatpak/exports/share/applications"
        "$HOME/.local/share/applications"
        "$HOME/.local/share/flatpak/exports/share/applications"
    )
    local dir f

    for dir in "${dirs[@]}"; do
        [ -d "$dir" ] || continue
        while IFS= read -r -d '' f; do
            procesar_desktop_file "$f"
        done < <(find "$dir" -maxdepth 1 -name '*.desktop' -print0 2>/dev/null)
    done

    ordenar_arrays_avanzado
}

# Muestra la simulación real de "apt-get -s purge" para los paquetes dados
# (incluye cualquier dependiente que apt decida arrastrar), pide
# confirmación final y, si se acepta, ejecuta el purge de verdad.
# Recibe los nombres de dos arrays (por referencia) con los paquetes a
# purgar: $1 = array de nombres visibles, $2 = array de paquetes.
confirmar_y_purgar_avanzado() {
    local -n _adv_names="$1"
    local -n _adv_pkgs="$2"

    header
    echo "Calculando el plan de desinstalación (simulación, no se borra nada todavía)..."
    echo

    local salida sim_status
    salida=$(sudo apt-get -s purge "${_adv_pkgs[@]}" 2>&1)
    sim_status=$?

    if [ "$sim_status" -ne 0 ]; then
        if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
            calcular_dimensiones_whiptail
            whiptail --title "$WT_TITLE" --scrolltext --ok-button "Aceptar" \
                --msgbox "No se pudo calcular un plan de desinstalación; apt devolvió un error:\n\n$salida" \
                "$WT_HEIGHT_BIG" "$WT_WIDTH_BIG"
        else
            header
            echo "No se pudo calcular un plan de desinstalación; apt devolvió un error:"
            echo
            echo "$salida"
            pause
        fi
        return
    fi

    local resumen="Se eliminarán:\n\n"
    local name
    for name in "${_adv_names[@]}"; do
        resumen+="  ✓ $name\n"
    done

    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        calcular_dimensiones_whiptail
        whiptail --title "$WT_TITLE" --scrolltext --ok-button "Aceptar" \
            --msgbox "Este es el plan REAL que ejecutaría apt (simulación de 'apt-get -s purge'), incluyendo cualquier paquete dependiente que se arrastre:\n\n$salida" \
            "$WT_HEIGHT_BIG" "$WT_WIDTH_BIG"

        if ! whiptail --title "$WT_TITLE" --scrolltext --yes-button "Sí, eliminar" --no-button "Cancelar" --yesno "${resumen}\n¿Confirmas la desinstalación? Esta acción no se puede deshacer." "$WT_HEIGHT" "$WT_WIDTH"; then
            return
        fi
    else
        header
        echo "Plan REAL que ejecutaría apt (simulación de 'apt-get -s purge'),"
        echo "incluyendo cualquier paquete dependiente que se arrastre:"
        echo
        echo "$salida"
        echo
        echo -e "$resumen"
        local confirm
        read -rp "¿Confirmas la desinstalación de los paquetes anteriores? [s/N]: " confirm
        if [[ ! "$confirm" =~ ^[sS]$ ]]; then
            echo "Operación cancelada."
            pause
            return
        fi
    fi

    ejecutar_purge "${_adv_pkgs[@]}"
}

# Opción 3 — selección con whiptail (checkboxes)
buscar_otras_aplicaciones_whiptail() {
    calcular_dimensiones_whiptail

    local -a checklist_args=()
    local i
    for i in "${!ADV_NAMES[@]}"; do
        checklist_args+=("$((i+1))" "${ADV_NAMES[$i]}  [${ADV_PACKAGES[$i]}]" "OFF")
    done

    local altura_lista=$(( ${#ADV_NAMES[@]} < WT_LISTHEIGHT ? ${#ADV_NAMES[@]} : WT_LISTHEIGHT ))

    local seleccion
    seleccion=$(whiptail --title "$WT_TITLE" \
        --ok-button "Aceptar" --cancel-button "Cancelar" \
        --checklist "MODO AVANZADO: apps a eliminar.\n(↑ ↓ mover | Espacio: marcar | TAB: ir a Aceptar/Cancelar | Enter: confirmar)" \
        "$WT_HEIGHT" "$WT_WIDTH" "$altura_lista" \
        "${checklist_args[@]}" \
        3>&1 1>&2 2>&3)
    local wt_status=$?

    [ "$wt_status" -ne 0 ] && return

    if [ -z "$seleccion" ]; then
        whiptail --title "$WT_TITLE" --ok-button "Aceptar" --msgbox "No se ha seleccionado ninguna aplicación." "$WT_HEIGHT" "$WT_WIDTH"
        return
    fi

    local -a to_remove_names=() to_remove_pkgs=() tags
    local tag idx
    read -ra tags <<< "${seleccion//\"/}"
    for tag in "${tags[@]}"; do
        idx=$((tag-1))
        to_remove_names+=("${ADV_NAMES[$idx]}")
        to_remove_pkgs+=("${ADV_PACKAGES[$idx]}")
    done

    confirmar_y_purgar_avanzado to_remove_names to_remove_pkgs
}

# Opción 3 — selección en texto plano (fallback sin whiptail)
buscar_otras_aplicaciones_texto() {
    local -a selected
    local i
    for i in "${!ADV_NAMES[@]}"; do
        selected[i]=0
    done

    while true; do
        header
        echo -e "${C_WARN}MODO AVANZADO${C_RESET} — aplicaciones detectadas por lanzador de menú"
        echo "(escriba el número para marcar/desmarcar, 'c' para confirmar, '0' para volver)"
        echo

        for i in "${!ADV_NAMES[@]}"; do
            local num
            num=$(printf '%2d' "$((i+1))")
            if [ "${selected[$i]}" -eq 1 ]; then
                # Marcada: línea completa en bloque negro-sobre-verde.
                echo -e "  ${num}) ${C_MARK} ☑ ${ADV_NAMES[$i]} [${ADV_PACKAGES[$i]}] ${C_RESET}"
            else
                echo -e "  ${num}) ☐ ${ADV_NAMES[$i]} ${C_TITLE}[${ADV_PACKAGES[$i]}]${C_RESET}"
            fi
        done

        echo
        local choice
        read -rp "> " choice

        case "$choice" in
            0)
                return
                ;;
            c|C)
                break
                ;;
            ''|*[!0-9]*)
                echo -e "${C_ERR}Opción no válida.${C_RESET}"
                sleep 1
                ;;
            *)
                # 10#$choice fuerza base 10: sin esto, Bash interpreta un
                # cero a la izquierda ("010", "018"...) como octal.
                local idx=$((10#$choice - 1))
                if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#ADV_NAMES[@]}" ]; then
                    if [ "${selected[$idx]}" -eq 1 ]; then
                        selected[idx]=0
                    else
                        selected[idx]=1
                    fi
                else
                    echo -e "${C_ERR}Número fuera de rango.${C_RESET}"
                    sleep 1
                fi
                ;;
        esac
    done

    local -a to_remove_names=() to_remove_pkgs=()
    for i in "${!ADV_NAMES[@]}"; do
        if [ "${selected[$i]}" -eq 1 ]; then
            to_remove_names+=("${ADV_NAMES[$i]}")
            to_remove_pkgs+=("${ADV_PACKAGES[$i]}")
        fi
    done

    if [ "${#to_remove_names[@]}" -eq 0 ]; then
        header
        echo "No se ha seleccionado ninguna aplicación."
        pause
        return
    fi

    confirmar_y_purgar_avanzado to_remove_names to_remove_pkgs
}

# Opción 3 — despachador: escanea, avisa del modo avanzado y delega según
# la interfaz disponible.
buscar_otras_aplicaciones() {
    header
    calcular_dimensiones_whiptail
    echo "Escaneando lanzadores del menú de aplicaciones..."
    escanear_lanzadores_detectar

    if [ "${#ADV_NAMES[@]}" -eq 0 ]; then
        local msg="No se ha detectado ninguna aplicación adicional fuera del catálogo curado."
        if [ "${#ADV_UNMANAGED_NAMES[@]}" -gt 0 ]; then
            msg+="\n\nSe encontraron ${#ADV_UNMANAGED_NAMES[@]} lanzador(es) sin paquete apt asociado (posible Flatpak/Snap/instalación manual), que no se pueden gestionar desde aquí:\n"
            local n
            for n in "${ADV_UNMANAGED_NAMES[@]}"; do
                msg+="  - $n\n"
            done
        fi

        if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
            whiptail --title "$WT_TITLE" --scrolltext --ok-button "Aceptar" --msgbox "$msg" "$WT_HEIGHT_BIG" "$WT_WIDTH_BIG"
        else
            header
            echo -e "$msg"
            pause
        fi
        return
    fi

    local aviso="MODO AVANZADO\n\nEsta opción escanea TODOS los lanzadores del menú de aplicaciones, no solo el catálogo curado de la Opción 2. Se excluyen automáticamente los componentes del sistema conocidos (Cinnamon, Nemo, Terminal, gestor de paquetes, red, etc.) y los paquetes que dpkg marca como esenciales o importantes, pero aun así revisa la lista con cuidado antes de confirmar.\n\nAntes de borrar nada se te mostrará el plan real de apt (simulación), incluyendo cualquier paquete dependiente que se arrastre.\n\nSe detectaron ${#ADV_NAMES[@]} aplicaciones adicionales."
    if [ "${#ADV_UNMANAGED_NAMES[@]}" -gt 0 ]; then
        aviso+="\n(${#ADV_UNMANAGED_NAMES[@]} lanzador(es) más no tienen paquete apt asociado y no se muestran aquí: probablemente Flatpak, Snap o instalación manual.)"
    fi

    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        whiptail --title "$WT_TITLE" --scrolltext --ok-button "Aceptar" --msgbox "$aviso" "$WT_HEIGHT_BIG" "$WT_WIDTH_BIG"
        buscar_otras_aplicaciones_whiptail
    else
        header
        echo -e "$aviso"
        pause
        buscar_otras_aplicaciones_texto
    fi
}

# ----------------------------------------------------------------------------
# Opción 4: Limpiar
# ----------------------------------------------------------------------------
limpiar_sistema() {
    header
    echo "Limpiando el sistema..."
    echo

    local before after freed freed_mb
    before=$(df --output=avail -B1 / | tail -1 | tr -d ' ')

    sudo DEBIAN_FRONTEND=noninteractive apt autoremove -y
    sudo DEBIAN_FRONTEND=noninteractive apt autoclean -y

    after=$(df --output=avail -B1 / | tail -1 | tr -d ' ')
    freed=$(( after - before ))
    if [ "$freed" -lt 0 ]; then
        freed=0
    fi
    freed_mb=$(( freed / 1024 / 1024 ))

    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        calcular_dimensiones_whiptail
        whiptail --title "$WT_TITLE" --ok-button "Aceptar" --msgbox "Limpieza completada.\n\nDependencias eliminadas.\nCaché de paquetes limpiada.\nEspacio recuperado (aprox.): ${freed_mb} MB" "$WT_HEIGHT" "$WT_WIDTH"
    else
        echo
        echo -e "${C_OK}Limpieza completada.${C_RESET}"
        echo
        echo "Dependencias eliminadas."
        echo "Caché de paquetes limpiada."
        echo "Espacio recuperado (aprox.): ${freed_mb} MB"
        pause
    fi
}

# ----------------------------------------------------------------------------
# Menú principal
# ----------------------------------------------------------------------------
main_menu_whiptail() {
    while true; do
        calcular_dimensiones_whiptail
        local opt
        opt=$(whiptail --title "$WT_TITLE" \
            --ok-button "Aceptar" --cancel-button "Salir" \
            --menu "Seleccione una opción (↑ ↓ + Enter; TAB para ir a los botones):" "$WT_HEIGHT" "$WT_WIDTH" 5 \
            "1" "Detectar programas" \
            "2" "Desinstalar programas" \
            "3" "Buscar otras aplicaciones (avanzado)" \
            "4" "Limpiar" \
            "0" "Salir" \
            3>&1 1>&2 2>&3)
        local wt_status=$?

        if [ "$wt_status" -ne 0 ]; then
            # ESC o Cancelar
            clear
            exit 0
        fi

        case "$opt" in
            1) detectar_programas ;;
            2) desinstalar_programas ;;
            3) buscar_otras_aplicaciones ;;
            4) limpiar_sistema ;;
            0) clear; echo "Saliendo..."; exit 0 ;;
        esac
    done
}

main_menu_texto() {
    while true; do
        header
        echo "1. Detectar programas"
        echo "2. Desinstalar programas"
        echo "3. Buscar otras aplicaciones (avanzado)"
        echo "4. Limpiar"
        echo "0. Salir"
        echo
        local opt
        read -rp "Seleccione una opción: " opt

        case "$opt" in
            1) detectar_programas ;;
            2) desinstalar_programas ;;
            3) buscar_otras_aplicaciones ;;
            4) limpiar_sistema ;;
            0) echo "Saliendo..."; exit 0 ;;
            *) echo -e "${C_ERR}Opción no válida.${C_RESET}"; sleep 1 ;;
        esac
    done
}

main_menu() {
    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        main_menu_whiptail
    else
        main_menu_texto
    fi
}

# ----------------------------------------------------------------------------
# Comprobaciones previas
# ----------------------------------------------------------------------------
# No debe ejecutarse ya como root: el propio script pide sudo solo para los
# comandos de apt, y arrancar con sudo por delante cambiaría $HOME al de
# root, rompiendo el escaneo de lanzadores de usuario de la Opción 3.
if [ "$EUID" -eq 0 ]; then
    echo "No ejecutes MintApp Remover como root ni con sudo."
    echo "El propio script pedirá la contraseña de administrador solo cuando la necesite."
    exit 1
fi

# Con $TERM vacío o "dumb" (lanzadores .desktop, wrappers, etc.) whiptail
# puede dibujarse pero dejar de responder a Intro/Espacio; se fuerza un
# valor razonable antes de arrancar cualquier diálogo.
if [ -z "${TERM:-}" ] || [ "$TERM" = "dumb" ]; then
    export TERM=linux
fi

if ! command -v dpkg >/dev/null 2>&1; then
    echo "MintApp Remover requiere dpkg y está pensado para distros basadas en Debian/Ubuntu."
    exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
    echo "MintApp Remover requiere apt."
    exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
    echo "MintApp Remover requiere sudo para instalar/desinstalar paquetes."
    exit 1
fi

# Primera pantalla del programa (instrucciones de manejo), una única vez.
mostrar_instrucciones_navegacion

main_menu
