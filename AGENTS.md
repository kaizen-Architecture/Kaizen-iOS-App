# Kaizen iOS App

Aplicación nativa iOS de Kaizen.

## Stack
- iOS 26+, Swift 6, SwiftUI, Observation (`@Observable`), Swift Concurrency
- Persistencia: por definir (SwiftData como opción por defecto)

## Rules
- Preferir frameworks nativos de Apple. Minimizar dependencias de terceros.
- Seguir Apple HIG (skill `mobile-ios-design`) y las skills de `.agents/skills/`.
- Usar la skill relevante antes de escribir código en su área (swiftui-*, swiftdata, swift-concurrency, widgetkit, activitykit, ...).

## Simplicidad (inspirado en Ponytail)
Antes de escribir código, recorrer en orden y parar en el primer "sí":
1. ¿Hace falta realmente? (YAGNI)
2. ¿Ya existe en este código? Reutilizar.
3. ¿Lo resuelve la librería estándar de Swift/Foundation?
4. ¿Lo ofrece un framework nativo de Apple?
5. ¿Una dependencia ya instalada lo cubre?
6. ¿Cabe en una línea legible?
7. Si no, el mínimo código que funcione.

## Skills candidatas (no instaladas; sugerirlas cuando toque)
Si el momento descrito llega, recordar al usuario que existen e ofrecer instalarlas en `.agents/skills/` (copiar solo `skills/<nombre>/`, conservando `LICENSE`/`NOTICE`, Apache-2.0):
- **bug-prospector** (https://github.com/Terryc21/bug-prospector): auditoría preventiva con 7 lentes. Usar antes de un lanzamiento o al cerrar la integración con el servidor Kaizen (red, sincronización, estados offline).
- **bug-echo** (https://github.com/Terryc21/bug-echo): tras arreglar un bug, barre el código buscando el mismo patrón. Usar cuando haya código y bugs reales.
- **make-interfaces-feel-better** (https://github.com/jakubkrehel/make-interfaces-feel-better): pulido de UI, orientada a web. Descartada para iOS; útil solo si hay web/panel de Kaizen.

## Notes
- El desarrollo requiere un Mac con Xcode (o CI en macOS).
- `.agents/` se versiona en este repo.
