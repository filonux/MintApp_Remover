<p align="center">
  <img src="assets/icon.png" width="128" alt="Icono de MintApp Remover">
</p>

<h1 align="center">MintApp Remover</h1>

<p align="center">
  Desinstalador de aplicaciones preinstaladas para Linux Mint 22.3 Cinnamon.<br>
  Un script de Bash, sin dependencias raras, que te muestra exactamente qué va a borrar antes de borrarlo.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licencia-GPLv3-3b82f6.svg" alt="Licencia GPLv3"></a>
  <img src="https://img.shields.io/badge/bash-5.x-22c55e.svg" alt="Bash 5.x">
  <img src="https://img.shields.io/badge/idioma-espa%C3%B1ol-3b82f6.svg" alt="Español">
</p>

---

## Qué es 

Es una herramienta pequeña y directa para una tarea concreta: quitar programas de forma ordenada, sin sorpresas. 

Empiezas con tu Linux Mint 22.3 y seguro que hay algún programa que nunca utilizarás. Esta herramienta ya contempla todos los programas preinstalados en Linux Mint 22.3, además, se le añade otra opción que permite desinstalar cualquier otro programa que tengas instalados.

Todo esto lo haces desde una bonita y sencilla terminal, para terminar haciendo automáticamente una limpieza de las dependencias. 

Linux Mint 22.3 Cinnamon viene con una buena cantidad de aplicaciones instaladas de fábrica: Hypnotix, Warpinator, Rhythmbox, Pix, Celluloid, herramientas de Mint como `mintstick` o `mintbackup`, etc. Muchas son útiles. Otras, según cómo uses tu equipo, simplemente ocupan espacio en el menú.

Quitarlas a mano implica saber el nombre exacto del paquete (que no siempre coincide con el nombre visible en el menú) y confiar en que `apt purge` no se lleve algo que no debería. **MintApp Remover** resuelve las dos cosas: te da una lista con casillas de las aplicaciones de usuario típicas de Mint, y antes de desinstalar nada te enseña el resultado real de la operación.

No es un "optimizador" ni promete liberar gigas milagrosos. 


<img width="740" height="436" alt="1 pantalla-inicio-terminal" src="https://github.com/user-attachments/assets/981f1d8a-78da-479f-a09d-11b389ae0466" />
<img width="738" height="438" alt="2 inicio-mintappremover" src="https://github.com/user-attachments/assets/cffa6472-20d1-45a6-a67f-850565e43d6c" />
<img width="742" height="435" alt="3 detecta-apps-mint" src="https://github.com/user-attachments/assets/7e9ef22b-591c-4e92-876d-bf9678b89d5f" />
<img width="742" height="437" alt="4 desinstalar-mint" src="https://github.com/user-attachments/assets/f7a029f9-c310-492a-870e-fb612ccf8a10" />
<img width="751" height="437" alt="5 desinstalar-modoavanzado" src="https://github.com/user-attachments/assets/2620c815-2577-46bf-aaeb-f11e4c6e278f" />
<img width="746" height="411" alt="6 desinstalar-modoavanzado2" src="https://github.com/user-attachments/assets/1f290a51-a6ac-4041-a8b4-e7dd69069adb" />
<img width="743" height="431" alt="7 limpiar-dependencias" src="https://github.com/user-attachments/assets/691b66cb-e7a9-4466-95d4-b4886405aa60" />


## Ventaja

La mayoría de los scripts de este estilo que circulan por foros son una lista fija de `sudo apt purge paquete1 paquete2 paquete3...`. Si algún nombre de paquete cambió entre versiones de Mint, o si tienes algo instalado que el autor del script no consideró, te quedas a medias o —peor— confías ciegamente en una lista que no revisaste.

MintApp Remover hace dos cosas distintas al respecto:

- **Nunca ejecuta un `purge` sin que antes veas el plan real de apt.** En el modo avanzado, antes de preguntar "¿confirmas?" se ejecuta `apt-get -s purge` (simulación, no borra nada) y se te muestra tal cual, incluyendo cualquier paquete dependiente que apt decida arrastrar.
- **El modo avanzado no depende de una lista fija.** En vez de asumir nombres de paquete, escanea los lanzadores reales del menú de aplicaciones (`.desktop`) y le pregunta a `dpkg` de quién es cada uno. Así encuentra aplicaciones que el catálogo curado no contempla, sin que haya que mantener esa lista actualizada a mano para que siga funcionando.

A eso se suma que el script funciona igual con o sin `whiptail` instalado (interfaz gráfica de terminal con casillas, o un menú de texto plano equivalente como respaldo), así que no depende de paquetes adicionales para dar una experiencia decente.

## Instalación

Necesitas un sistema basado en Debian/Ubuntu con `bash`, `apt` y `dpkg` (ver [Compatibilidad](#compatibilidad)). No hace falta instalar nada más: `whiptail` es opcional y, si no está, el script usa su propio menú de texto.

Hay disponibles dos iconos en la carpeta assets para personalizarlo e integrarlo con tu sistema.

**Clonar el repositorio o descargar zip repositorio:**

```bash
git clone https://github.com/filonux/mintapp_remover.git
cd mintapp_remover
chmod +x script/MintApp_Remover.sh
./script/MintApp_Remover.sh
```

El script se ejecuta como usuario normal. Solo pedirá tu contraseña (vía `sudo`) en el momento en que de verdad vaya a instalar/desinstalar algo con `apt`, nunca antes.

## Uso

Al arrancar, la primera pantalla explica cómo moverse (se muestra una única vez). En resumen:

| Tecla | Acción |
|---|---|
| `↑` / `↓` | Moverse por la lista |
| `Espacio` | Marcar / desmarcar una aplicación |
| `Tab` | Cambiar el foco entre la lista y los botones (Aceptar / Cancelar) |
| `Enter` | Confirmar la opción u botón resaltado |

> Escribir el número de una opción **no la selecciona** en el modo gráfico (whiptail); ese atajo solo existe en el menú de texto plano de respaldo, donde sí está pensado para escribirse.

Desde el menú principal se accede a las cuatro funciones del programa:

```
1. Detectar programas
2. Desinstalar programas
3. Buscar otras aplicaciones (avanzado)
4. Limpiar
0. Salir
```

## Funciones

### 1 · Detectar programas

Recorre un catálogo curado a mano de aplicaciones de usuario que Linux Mint 22.3 instala por defecto (Firefox, Thunderbird, LibreOffice, Warpinator, Hypnotix, Rhythmbox, Celluloid, herramientas propias de Mint como `mintstick` o `mintbackup`, entre otras — la lista completa está en el propio script, array `CATALOG`) y comprueba con `dpkg-query` cuáles están realmente instaladas en tu equipo. Solo muestra las que encuentra instaladas; es un paso de diagnóstico, no borra nada.

### 2 · Desinstalar programas

Ejecuta automáticamente la detección si no se ha hecho antes, y presenta esa lista con casillas para marcar lo que quieres quitar. Tras confirmar, ejecuta `apt purge` sobre los paquetes seleccionados (elimina también los ficheros de configuración, no solo el binario).

### 3 · Buscar otras aplicaciones (avanzado)

Este es el modo que no depende del catálogo fijo. Escanea `/usr/share/applications` y `~/.local/share/applications`, identifica cada lanzador `.desktop` visible en el menú, y usa `dpkg -S` para averiguar a qué paquete pertenece. De ahí se descarta automáticamente:

- lo que ya está en el catálogo de la Opción 2 (para no repetirlo),
- componentes del propio sistema (Cinnamon, Nemo, gestor de red, gestor de paquetes, terminal, etc.) mediante una lista de patrones,
- cualquier paquete que `dpkg` marque como `Essential` o de prioridad `required`/`important`.

Aun con esos filtros, antes de purgar de verdad **siempre** se muestra la simulación real de `apt-get -s purge` con el plan completo. Es el modo pensado para encontrar aplicaciones de terceros, extensiones de Cinnamon empaquetadas, o software que instalaste tú mismo y ya no usas.

### 4 · Limpiar

Ejecuta `apt autoremove` (quita dependencias huérfanas que dejaron las desinstalaciones) y `apt autoclean` (vacía la caché de paquetes `.deb` descargados), y muestra un cálculo aproximado del espacio recuperado en disco.

## Compatibilidad

El script está pensado y probado para **Linux Mint 22.3 Cinnamon**, pero el único requisito técnico duro es tener `apt` y `dpkg`:

- **Funciona igual** en Ubuntu y otras distros basadas en Debian/Ubuntu (Pop!_OS, Zorin, MX Linux, elementary OS, otras ediciones de Mint...). El script lo comprueba al arrancar y avisa si no encuentra `apt`/`dpkg`.
- La **Opción 2** (catálogo curado) es específica de Mint: en otra distro probablemente no detecte ninguna aplicación, porque paquetes como `mintstick`, `warpinator` o `xapp-*` no existen ahí.
- La **Opción 3** (modo avanzado) es la parte realmente portable, al no depender de una lista fija.
- La lista de exclusión de la Opción 3 cubre bien Cinnamon/Mint y parcialmente GNOME, pero **no** tiene patrones específicos para KDE Plasma o XFCE. En esos entornos, revisa la lista con más cuidado antes de confirmar — la simulación de apt sigue siendo la última red de seguridad.
- **No es compatible** con distros que no usan apt/dpkg (Fedora, openSUSE, Arch Linux, etc.).

## Idioma

Tanto el script como este README están, por ahora, **únicamente en español**. Es un proyecto pequeño pensado inicialmente para uso propio y para la comunidad hispanohablante de Mint.

Si hay interés real (issues, estrellas, gente pidiéndolo), se evaluará crear una versión en inglés. Es una tarea de traducción directa — el script no tiene texto embebido en imágenes ni nada que complique el proceso — así que no haría falta reescribir la lógica.

## Roadmap (ideas, sin fecha comprometida)

- [ ] Versión en inglés del script y del README, si hay suficiente interés
- [ ] Ampliar el catálogo curado a otras ediciones de Mint (XFCE, MATE)
- [ ] Lista de exclusión más completa para KDE Plasma y XFCE en el modo avanzado
- [ ] Explorar un empaquetado `.deb` opcional

## Contribuir

Las contribuciones son bienvenidas. Antes de abrir un *issue* o un *pull request*, échale un vistazo a [`CONTRIBUTING.md`](.github/CONTRIBUTING.md) y al [`CODE_OF_CONDUCT.md`](.github/CODE_OF_CONDUCT.md). Para reportar una vulnerabilidad de seguridad, sigue el proceso descrito en [`SECURITY.md`](.github/SECURITY.md) en vez de abrir un issue público.

## Licencia

MintApp Remover es software libre distribuido bajo los términos de la **GNU General Public License versión 3 (GPLv3)**. Consulta el archivo [`LICENSE`](LICENSE) para el texto completo.

Copyright (C) 2026 Filonux
