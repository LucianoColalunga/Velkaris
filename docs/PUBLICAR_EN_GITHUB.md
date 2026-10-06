# Publicar Velkaris en GitHub (guía para el autor)

## 1. Crear el repositorio vacío
1. Entra en <https://github.com/new> con la cuenta **LucianoColalunga**.
2. *Repository name:* `Velkaris`. Público o privado, como prefieras.
3. **No** marques "Add a README", ".gitignore" ni "license": el proyecto ya los trae.
4. Pulsa **Create repository**.

## 2. Subir el código (desde la carpeta del proyecto)

```bash
git init -b main
```

```bash
git add .
```

```bash
git commit -m "Velkaris MVP: servidor autoritativo, 3 reinos, 3 clases y asedio"
```

```bash
git remote add origin https://github.com/LucianoColalunga/Velkaris.git
```

```bash
git push -u origin main
```

La primera vez, Git abrirá el navegador para iniciar sesión en GitHub (Git Credential Manager).

> `.gitignore` excluye `build/`, `.godot/` y `server.cfg` (que puede contener tu contraseña).
> Comprueba con `git status` que no se sube nada privado antes del primer `push`.

## 3. Publicar una versión descargable (Release)

**Automático (GitHub Actions):** crea y sube una etiqueta. El workflow compila y adjunta los `.zip`.

```bash
git tag v0.1.0
```

```bash
git push origin v0.1.0
```

Sigue el progreso en la pestaña **Actions**. Al terminar, los `.zip` aparecen en **Releases**.

**Manual:**
1. Ejecuta `compilar.bat -Zip`.
2. En GitHub: **Releases → Draft a new release**, etiqueta `v0.1.0`.
3. Adjunta `build\Velkaris-Windows-x64.zip` y `build\Velkaris-Server-Windows-x64.zip`.
4. **Publish release**. Comparte el enlace con tus amigos.

## 4. Antes de cada nueva versión
- Si cambias algo del protocolo de red (RPC, formato de snapshots o reglas validadas por el servidor),
  incrementa `Protocol.VERSION` en `scripts/shared/protocol.gd`, para que las versiones viejas
  reciban un aviso claro en lugar de comportarse de forma extraña.
- Actualiza `config/version` en `project.godot` y `application/file_version` en `export_presets.cfg`.
