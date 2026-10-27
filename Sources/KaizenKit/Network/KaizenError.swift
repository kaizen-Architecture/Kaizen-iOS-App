import Foundation

/// Errores de red de Kaizen con mensajes pensados para el usuario final (ES/EN).
public enum KaizenError: LocalizedError, Sendable, Equatable {
    case invalidServerURL
    case cannotReachServer(host: String)
    case timedOut(host: String)
    case invalidCredentials
    case tokenRejected
    case apiDisabled
    case server(status: Int)
    case unexpectedResponse

    public var errorDescription: String? { userMessage(language: "es") }

    /// Mensaje explicativo en el idioma de la app (`es` por defecto, `en` para inglés).
    public func userMessage(language: String) -> String {
        let es = language != "en"
        switch self {
        case .invalidServerURL:
            return es
                ? "La dirección del servidor no es válida. Usa el formato http://192.168.1.10:3333"
                : "The server address is not valid. Use a format like http://192.168.1.10:3333"
        case .cannotReachServer(let host):
            return es
                ? "No se puede conectar con \(host). Comprueba que el servidor Kaizen está encendido, que el iPad está en la misma red Wi-Fi y que la IP y el puerto son correctos. Si iOS preguntó por la red local, permítela en Ajustes ▸ Kaizen ▸ Red local."
                : "Can't reach \(host). Check that the Kaizen server is running, that this iPad is on the same Wi-Fi network and that the IP and port are right. If iOS asked about the local network, allow it in Settings ▸ Kaizen ▸ Local Network."
        case .timedOut(let host):
            return es
                ? "El servidor \(host) tarda demasiado en responder. Comprueba la red y que Kaizen no esté bloqueado."
                : "The server \(host) is taking too long to respond. Check your network and that Kaizen isn't stuck."
        case .invalidCredentials:
            return es ? "Usuario o contraseña incorrectos." : "Wrong username or password."
        case .tokenRejected:
            return es
                ? "El servidor ha rechazado el acceso a la API. Falta el API Token o no es válido. Cópialo desde Kaizen ▸ Usuarios y vuelve a iniciar sesión."
                : "The server refused API access. The API Token is missing or invalid. Copy it from Kaizen ▸ Users and sign in again."
        case .apiDisabled:
            return es
                ? "La API está desactivada en el servidor. Actívala en los ajustes de Kaizen."
                : "The API is disabled on the server. Enable it in Kaizen's settings."
        case .server(let status):
            return es
                ? "El servidor respondió con un error (\(status))."
                : "The server answered with an error (\(status))."
        case .unexpectedResponse:
            return es
                ? "Respuesta inesperada. ¿Seguro que la dirección apunta a un servidor Kaizen?"
                : "Unexpected response. Are you sure the address points to a Kaizen server?"
        }
    }
}

/// Normaliza lo que escribe el usuario en el campo de servidor.
public enum ServerURL {
    /// Acepta `192.168.1.10:3333`, `http://host:3333/`, etc. Devuelve `nil` si no es usable.
    public static func parse(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text),
              let host = url.host, !host.isEmpty,
              url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }
}
