# Kaizen iOS

<p align="center">
  <img src="kaizen.png" alt="Kaizen Logo" width="128" />
</p>

<p align="center">
  <b>Native manga reading and management client for iOS (SwiftUI, iOS 26+).</b>
</p>

<p align="center">
  <a href="#-download-ipa">Download IPA</a> •
  <a href="#-installation-guide-sideloading">Sideloading Guide</a> •
  <a href="#-connecting-to-kaizen-server-local-vpn-or-remote">Server & VPN Setup</a> •
  <a href="#-development--building">Development</a> •
  <a href="#-guía-en-español">Versión en Español</a>
</p>

---

## 📥 Download IPA

Anyone can download the pre-packaged application ready for sideloading:

- **Latest Release / Pre-Release:** Visit the [**GitHub Releases**](../../releases) page.
- **Available assets:**
  - `Kaizen_vX.Y.Z.ipa`: Versioned package ready for signing and installing.
  - `Kaizen.ipa`: Direct link to the latest packaged build.
- **GitHub Actions Artifacts:** You can also navigate to the **Actions** tab > click on the latest successful workflow run > download the `Kaizen-vX.Y.Z-IPA` artifact bundle.

---

## 📲 Installation Guide (Sideloading)

Because Kaizen is a self-hosted, open-source application without commercial distribution on the Apple App Store, it is installed via **Sideloading** using your Apple ID (free or developer account).

Choose your preferred tool:

### Option A: AltStore (Recommended for Windows & Mac)

1. **Install AltServer on your PC/Mac:**
   - Download AltServer from [altstore.io](https://altstore.io).
   - *Windows users:* Ensure you install the official direct builds of **iTunes** and **iCloud** (from Apple's website, not from the Microsoft Store).
2. **Install AltStore on your iPhone:**
   - Connect your iPhone to your computer using a USB cable.
   - Launch AltServer from your system tray/menu bar > Click **Install AltStore** > Select your device and enter your Apple ID credentials.
   - On your iPhone, open **Settings > General > VPN & Device Management** and trust your developer certificate.
   - *iOS 16+:* Turn on **Developer Mode** in **Settings > Privacy & Security > Developer Mode** (reboot required).
3. **Install Kaizen:**
   - Download the `Kaizen.ipa` file directly on your iPhone using Safari.
   - Open **AltStore** > go to the **My Apps** tab > tap the **`+`** icon in the top-left corner.
   - Select the downloaded `Kaizen.ipa`. AltStore will sign and install the app to your Home Screen.

---

### Option B: Sideloadly (Fast & direct via USB or Wi-Fi)

1. Download and install **Sideloadly** from [sideloadly.io](https://sideloadly.io) on your PC or Mac.
2. Connect your iPhone to your computer and launch Sideloadly.
3. Drag and drop the `Kaizen.ipa` file into the Sideloadly window.
4. Enter your Apple ID email.
5. Click **Start**. In a few moments, Kaizen will be installed on your device.
6. If this is your first time sideloading, trust your certificate under **Settings > General > VPN & Device Management**.

---

### Option C: SideStore (Computer-free on-device refreshing)

1. Follow the official setup instructions at [sidestore.io](https://sidestore.io) to initialize SideStore.
2. Download `Kaizen.ipa` on your iPhone.
3. Open SideStore, tap `+`, select the `.ipa`, and let SideStore sign it using its local WireGuard loopback VPN.

> [!NOTE]
> Free Apple IDs permit app signatures for **7 days**. AltStore and SideStore automatically refresh the signature in the background when connected to the same local Wi-Fi or via SideStore's VPN.

---

## 🌐 Connecting to Kaizen Server (Local, VPN or Remote)

Kaizen iOS connects to your self-hosted Kaizen backend instance. By default, **production runs on port `3000`** (staging and test environments typically use port `3333`).

When you launch the app, provide:
- **Server URL**: Your server address including port or domain.
- **Username & Password**: Your credentials.
- **API Token**: Found in your Kaizen web dashboard user profile settings.

### Connection Scenarios

#### 1. Local Network (Home Wi-Fi)
- Connect your iPhone to the same Wi-Fi network as your server.
- Enter your server's local IP and production port:
  ```text
  http://192.168.1.XX:3000
  ```
- *Note:* On first launch, iOS will request **Local Network** access. Tap **Allow** to enable discovery and socket communication.

#### 2. Remote Access via Private VPN (Tailscale, WireGuard) — *Recommended*
Access your library on the go without exposing open ports to the internet:
- **Tailscale**:
  1. Install Tailscale on both your Kaizen server and iPhone.
  2. Log in with the same account.
  3. Use the Tailscale IP (or MagicDNS hostname) with port 3000:
     ```text
     http://100.x.y.z:3000   or   http://my-server:3000
     ```
- **WireGuard / OpenVPN**:
  - Connect to your home VPN tunnel from iOS and use your normal local IP (`http://192.168.1.XX:3000`).

#### 3. Public Remote Access (Domain / Reverse Proxy / Port Forwarding)
- **Domain with Reverse Proxy (Recommended with HTTPS):**
  - If you use Cloudflare Tunnels, Nginx, Caddy, or Traefik proxying port 3000:
    ```text
    https://kaizen.yourdomain.com
    ```
- **Public IP / Dynamic DNS with Port Forwarding:**
  - Forward an external router port to port 3000 on your server:
    ```text
    http://your-public-ip:port
    # or
    http://your-host.ddns.net:port
    ```
  - *(Optional)* Internal development and staging instances use port `3333`.

---

## 🛠 Development & Building

To build the project manually from source:

```bash
# Requires macOS with Xcode 16+ and XcodeGen
brew install xcodegen

# Generate the Xcode project
xcodegen generate

# Open in Xcode
open Kaizen.xcodeproj
```

The CI workflow (`.github/workflows/ci.yml`) compiles, runs tests, and packages the `.ipa` automatically on pushes to `main` and release tags.

---

## 🇪🇸 Guía en Español

<details>
<summary><b>Haz clic aquí para ver la guía completa en español</b></summary>

### 📥 Descarga del IPA
- Puedes descargar el archivo `.ipa` compilado desde la sección de [**GitHub Releases**](../../releases).
- Descargas disponibles: `Kaizen_vX.Y.Z.ipa` (versionado) y `Kaizen.ipa` (última build).

### 📲 Instalación con Sideloading
1. **AltStore:** Instala AltServer en PC/Mac, instala AltStore en tu iPhone por USB, descarga el `.ipa` en Safari y pulsa `+` en AltStore para instalarlo.
2. **Sideloadly:** Conecta el iPhone, arrastra el `.ipa` a la ventana de Sideloadly, introduce tu Apple ID y pulsa Start.
3. **SideStore:** Permite firmar e instalar directamente desde el iPhone utilizando una VPN WireGuard local.
*Recuerda activar el Modo de Desarrollador en Ajustes > Privacidad y seguridad en iOS 16+ y confiar en tu certificado en Ajustes > General > Gestión de dispositivos y VPN.*

### 🌐 Conexión al Servidor (Puerto 3000 en Producción / 3333 en Staging)
- **Red Local (Wi-Fi):** `http://192.168.1.XX:3000` (concede permiso de red local en iOS al abrir la app).
- **VPN Privada (Tailscale / WireGuard):** Conéctate a Tailscale en el iPhone y usa `http://100.x.y.z:3000` o el MagicDNS de tu servidor. No requiere abrir puertos.
- **Dominio Público / Reverse Proxy:** Introduce `https://kaizen.tudominio.com` o tu IP externa con el puerto configurado.

</details>
