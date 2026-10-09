# Comandos del proyecto

Todos los comandos se ejecutan desde la raíz del proyecto.

## Primer arranque

1. Copia `src/config/.env.example` a `src/config/.env` y rellena los valores.
2. Crea la tabla en PostgreSQL:

   ```sql
   CREATE TABLE users (
     id SERIAL PRIMARY KEY,
     name TEXT NOT NULL,
     email TEXT NOT NULL
   );
   ```

3. Arranca el servidor con `zig build run`. La primera vez se descargan las dependencias.

## Desarrollo

| Comando | Qué hace |
|---|---|
| `zig build run` | Compila en modo Debug y arranca el servidor |
| `zig build test` | Ejecuta los tests unitarios (no necesitan base de datos) |
| `zig build test --summary all` | Igual, mostrando cuántos tests pasan |
| `zig build` | Solo compila; el binario y el `.env` quedan en `zig-out/bin/` |
| `zig fmt src` | Formatea el código |

Las variables de entorno tienen prioridad sobre el `.env`:

```bash
PORT=9000 zig build run                   # Git Bash
$env:PORT="9000"; zig build run           # PowerShell
ENV_FILE=otra/ruta/.env zig build run     # usar otro .env
```

## Build para producción

```bash
zig build -Doptimize=ReleaseSafe
```

| Modo | Cuándo usarlo |
|---|---|
| `ReleaseSafe` | Recomendado para el servidor: optimizado y con comprobaciones de seguridad |
| `ReleaseFast` | Máximo rendimiento, sin comprobaciones de desbordamiento ni de rangos |
| `ReleaseSmall` | Binario lo más pequeño posible |

### Compilar para Linux desde Windows

```bash
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl
zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-linux-musl   # servidores ARM
```

Genera un binario estático, sin dependencias del sistema. Con `--prefix dist` sale en
`dist/bin/` en lugar de `zig-out/bin/`.

## Ejecutar en el servidor

La build copia `src/config/.env` junto al binario, y el binario lee el `.env` de su propia
carpeta, se lance desde donde se lance. Basta con copiar `zig-out/bin/backend-zig` y
`zig-out/bin/.env` a la misma carpeta del servidor y arrancarlo, por ejemplo con systemd.

Para usar otro archivo, `ENV_FILE=/ruta/.env ./backend-zig`. Las variables de entorno
siempre tienen prioridad sobre el `.env`.

`HOST` vale `127.0.0.1` por defecto, así que solo acepta conexiones locales. Usa
`0.0.0.0` si el servidor recibe tráfico de fuera sin un proxy delante (por ejemplo, en un
contenedor).

## Dependencias

| Comando | Qué hace |
|---|---|
| `zig fetch --save <url>` | Añade una dependencia a `build.zig.zon` |
| `zig fetch --save git+https://github.com/karlseguin/pg.zig#master` | Actualiza pg.zig |

## Limpieza

```bash
rm -rf .zig-cache zig-out                     # Git Bash
Remove-Item -Recurse .zig-cache, zig-out      # PowerShell
```