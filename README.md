# Kaizen iOS

<p align="center">
  <img src="kaizen.png" alt="Kaizen Logo" width="128" />
</p>

<p align="center">
  <b>Aplicación nativa de lectura y gestión de manga para iOS (SwiftUI, iOS 26+).</b>
</p>

<p align="center">
  <a href="#-descarga-del-ipa">Descargar IPA</a> •
  <a href="#-guía-de-instalación-sideloading">Instalación (Sideloading)</a> •
  <a href="#-conexión-con-el-servidor-kaizen-local-vpn-o-remoto">Conexión y VPN</a> •
  <a href="#-desarrollo-y-compilación">Desarrollo</a>
</p>

---

## 📥 Descarga del IPA

Cualquier persona puede descargar e instalar la versión empaquetada lista para sideloading:

- **Última versión estable / pre-release:** Ve a la sección de [**GitHub Releases**](../../releases) del repositorio.
- **Descargas disponibles:**
  - `Kaizen_vX.Y.Z.ipa`: IPA versionada lista para firmar e instalar.
  - `Kaizen.ipa`: Enlace directo a la última build generada.
- **Artefactos de GitHub Actions:** También puedes ir a la pestaña **Actions** > seleccionar la última ejecución exitosa > descargar el artefacto `Kaizen-vX.Y.Z-IPA`.

---

## 📲 Guía de Instalación (Sideloading)

Como Kaizen es una aplicación auto-hospedada y de código abierto sin distribución comercial en el App Store, se instala usando **Sideloading** mediante tu cuenta de Apple ID (gratuita o de desarrollador).

Elige la herramienta que prefieras:

### Opción A: AltStore (Recomendada para Windows y Mac)

1. **Instalar AltServer en tu PC/Mac:**
   - Descarga AltServer desde [altstore.io](https://altstore.io).
   - En Windows, asegúrate de tener instalado **iTunes** e **iCloud** (versiones directas de Apple, no las de la Microsoft Store).
2. **Instalar AltStore en el iPhone:**
   - Conecta tu iPhone por cable al ordenador.
   - Abre AltServer en la bandeja del sistema > Haz clic en **Install AltStore** > Selecciona tu iPhone e introduce tu Apple ID.
   - En tu iPhone, ve a **Ajustes > General > Gestión de dispositivos y VPN** y confía en el certificado de tu cuenta.
   - En iOS 16 o superior: Activa el **Modo de desarrollador** en **Ajustes > Privacidad y seguridad > Modo de desarrollador** (requiere reiniciar el dispositivo).
3. **Instalar Kaizen:**
   - Descarga el archivo `.ipa` de Kaizen desde GitHub en tu iPhone (Safari).
   - Abre **AltStore** en tu iPhone > pestaña **My Apps** > pulsa el botón **`+`** arriba a la izquierda.
   - Selecciona el archivo `Kaizen.ipa` descargado. AltStore lo firmará y lo instalará en tu pantalla de inicio.

---

### Opción B: Sideloadly (Rápido y directo vía USB o Wi-Fi)

1. Descarga e instala **Sideloadly** desde [sideloadly.io](https://sideloadly.io) en tu PC o Mac.
2. Conecta tu iPhone al ordenador y abre Sideloadly.
3. Arrastra el archivo `Kaizen.ipa` a la ventana de Sideloadly.
4. Introduce tu Apple ID en el campo correspondiente.
5. Pulsa **Start**. En unos segundos la app aparecerá instalada en tu iPhone.
6. Si es la primera vez, ve a **Ajustes > General > Gestión de dispositivos y VPN** en tu iPhone y confía en tu perfil.

---

### Opción C: SideStore (Instalación autónoma sin PC continuo)

1. Sigue la guía oficial de [sidestore.io](https://sidestore.io) para inicializar SideStore.
2. Una vez tengas SideStore en tu iPhone, descarga el `.ipa` de Kaizen desde Safari.
3. Abre SideStore, pulsa `+`, selecciona el `.ipa` y se firmará automáticamente usando la VPN local de WireGuard de SideStore.

> [!NOTE]
> Las cuentas gratuitas de Apple ID permiten firmar apps durante **7 días**. AltStore y SideStore renuevan la firma automáticamente en segundo plano cuando estás conectado a la misma red Wi-Fi que tu ordenador (o mediante la VPN de SideStore).

---

## 🌐 Conexión con el Servidor Kaizen (Local, VPN o Remoto)

Kaizen iOS se conecta a tu instancia auto-hospedada del servidor Kaizen. Por defecto, en producción el servidor Kaizen corre en el puerto **`3000`** (mientras que entornos de pruebas/staging suelen usar el **`3333`**).

Al abrir la app por primera vez, introduce los siguientes datos:
- **URL del Servidor**: La dirección de tu servidor Kaizen con su puerto o dominio.
- **Usuario y Contraseña**
- **API Token**: Lo obtienes en el panel web de Kaizen (en los ajustes de tu perfil).

---

### Escenarios de Conexión

#### 1. Red Local (En casa por Wi-Fi)
- Tu iPhone debe estar en la misma red Wi-Fi que el servidor.
- Introduce la IP local de tu servidor y el puerto de producción:
  ```text
  http://192.168.1.XX:3000
  ```
- *Nota:* En el primer inicio, iOS te solicitará permiso para **Red Local**. Confírmalo para permitir el descubrimiento y la conexión.

#### 2. Acceso Remoto con VPN Privada (Tailscale, WireGuard, ZeroTier) — *Recomendado*
Si sales de casa y no quieres abrir puertos a internet:
- **Tailscale**:
  1. Instala Tailscale en tu servidor y en tu iPhone.
  2. Conéctate con la misma cuenta en ambos dispositivos.
  3. Usa la IP de Tailscale (o MagicDNS) con el puerto 3000:
     ```text
     http://100.x.y.z:3000  o  http://mi-servidor:3000
     ```
- **WireGuard / OpenVPN**:
  - Activa la VPN en tu iPhone e introduce la IP local habitual (`http://192.168.1.XX:3000`).

#### 3. Acceso Público (IP Externa / DNS Dinámico / Dominio Propio)
Si decides abrir Kaizen a internet:
- **Con Dominio / Reverse Proxy (Recomendado con HTTPS):**
  - Si tienes un subdominio gestionado por Cloudflare Tunnel, Nginx, Caddy o Traefik apuntando al puerto 3000:
    ```text
    https://kaizen.tudominio.com
    ```
- **Con IP Pública / DDNS y Port Forwarding:**
  - Si abres un puerto en tu router hacia el puerto 3000 del servidor:
    ```text
    http://tu-ip-publica:puerto_abierto
    # o bien
    http://tu-host.ddns.net:puerto_abierto
    ```
  - *(Opcional)* Entornos de desarrollo/staging internos pueden utilizar el puerto alternativo `3333`.

---

## 🛠 Desarrollo y Compilación

Para compilar el proyecto manualmente desde el código fuente:

```bash
# Requiere macOS con Xcode 16+ y XcodeGen
brew install xcodegen

# Generar el proyecto Xcode
xcodegen generate

# Abrir en Xcode
open Kaizen.xcodeproj
```

El pipeline de integración continua (`.github/workflows/ci.yml`) compila, pasa las pruebas unitarias y genera el archivo `.ipa` automáticamente en cada push a `main` y ante nuevos tags.
