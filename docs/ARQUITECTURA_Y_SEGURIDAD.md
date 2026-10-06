# Arquitectura técnica, rendimiento y seguridad

Documento de diseño y auditoría del MVP. Cada medida indica el archivo y la función donde está
implementada para poder revisarla en el código.

---

## 1. Motor: Godot 4 con renderer *Compatibility*

| Criterio | Godot 4.3+ | Unity | Unreal 5 |
|---|---|---|---|
| RAM del editor y del juego | Baja (editor de ~120 MB, sin instalación) | Media | Alta (no recomendable con 8 GB) |
| GPU de 2 GB | Renderer *Compatibility* (OpenGL 3.3) pensado para hardware modesto | Correcto con URP | Pesado por defecto |
| Servidor dedicado | El mismo binario con `--headless`, sin GPU | Build de servidor aparte | Build de servidor aparte |
| Red integrada | ENet (UDP fiable y no fiable, canales) + `SceneMultiplayer` con autenticación | Netcode for GameObjects / terceros | Replicación propia (compleja) |
| Licencia | MIT, sin royalties | Comercial | Royalties a partir de cierto ingreso |

**Decisión:** Godot 4 (mínimo 4.3), GDScript y renderer `gl_compatibility`.

### Presupuesto de rendimiento (objetivos de diseño)

> Son objetivos y estimaciones de diseño, no mediciones. Mídelos en tu PC con el contador de FPS del
> HUD y el Administrador de tareas.

| Recurso | Objetivo | Cómo se consigue |
|---|---|---|
| RAM del cliente | < 1 GB | Cero texturas; mallas primitivas compartidas; mundo generado por código |
| VRAM | < 300 MB | Sin texturas, `Sky.radiance_size = 32`, sombras desactivadas por defecto, sin MSAA |
| Draw calls | < 150 | `MultiMesh` para murallas, almenas, árboles y rocas; caché de materiales (`WorldView.mat`) |
| FPS | 60 con V-Sync | Textos del HUD actualizados a 10 Hz, efectos de vida corta, niebla para recortar lo lejano |
| Red (cliente) | ~3 KB/s de subida; ~30 KB/s de bajada con 32 jugadores en el área | Input a 30 Hz (3 comandos por paquete); snapshots a 15 Hz con área de interés de 75 m |
| CPU del servidor | 30 ticks/s en un núcleo | Sin motor de físicas: colisiones analíticas en `Movement.resolve`; `Engine.max_fps = 60` en headless |

---

## 2. Arquitectura de red

```
 CLIENTE (Velkaris.exe)                           SERVIDOR (VelkarisServer.exe --headless)
 ┌──────────────────────────┐  c2s_input  30 Hz   ┌──────────────────────────────────────┐
 │ Teclado -> intención     │ ──────────────────▶ │ Validación: tipo, rango, NaN, ritmo  │
 │ Predicción local         │  c2s_ability        │ Cola de comandos + fichas por tick   │
 │   (Movement.step)        │ ──────────────────▶ │ Simulación autoritativa a 30 Hz:     │
 │ Reconciliación           │  c2s_chat           │   movimiento, colisiones, combate,   │
 │ Interpolación (120 ms)   │                     │   capturas, portones y puntuación    │
 │ Render + HUD             │ ◀────────────────── │ Snapshot por destinatario:           │
 └──────────────────────────┘  s2c_snapshot 15 Hz │   área de interés + sigilo           │
                               s2c_event (fiable) └──────────────────────────────────────┘
```

- **Un único punto RPC** (`scripts/net/network.gd`, autoload `/root/Net`). Cliente y servidor
  comparten el mismo script, así que las firmas RPC siempre coinciden.
- **Canales ENet:** canal 0 fiable (habilidades, chat, eventos, bienvenida); canal 1
  `unreliable_ordered` (input y snapshots: si un paquete llega tarde, se descarta en vez de bloquear).
- **Tick fijo:** `physics_ticks_per_second = 30` en cliente y servidor. Un comando del cliente
  equivale exactamente a un tick de movimiento.

### Handshake de 3 fases (`game_server.gd`)
1. **Desafío:** al conectar, el servidor envía `{nonce de 128 bits, versión, ¿requiere contraseña?}`
   por el canal de autenticación de `SceneMultiplayer`. Mientras no termine la auth, Godot no
   entrega ningún RPC de ese peer.
2. **Respuesta:** el cliente envía `{versión, nombre, reino, clase, prueba}` en JSON (máx. 512 B),
   donde `prueba = SHA256(nonce + ":" + SHA256(contraseña))`. El servidor valida y llama a
   `complete_auth`.
3. **Listo:** el cliente envía `c2s_ready`; el servidor crea el personaje y responde con
   `s2c_welcome`. Si no llega en 10 s, se desconecta.

### Predicción, reconciliación e interpolación (`game_client.gd`)
- El cliente aplica su comando al instante con `Movement.step`, **el mismo código** que ejecuta el
  servidor, y guarda el comando como pendiente.
- Cada snapshot trae la posición autoritativa y el último comando procesado (`ack`). El cliente
  parte de la posición del servidor y vuelve a simular los pendientes. Las diferencias pequeñas se
  absorben visualmente (`render_offset`); las grandes (reaparición, carga) se aplican de golpe.
- Los demás jugadores se dibujan 120 ms en el pasado, interpolando entre snapshots.

---

## 3. Auditoría de seguridad: modelo de amenazas

**Principio rector:** *el cliente está en manos del adversario.* Puede estar modificado, enviar
cualquier byte y leer toda su memoria. Por eso el cliente solo envía **intenciones** y el servidor
solo envía lo que ese jugador **puede ver**.

| # | Amenaza | Mitigación | Dónde |
|---|---|---|---|
| 1 | **Speedhack** (acelerar el reloj o enviar comandos de más) | El servidor solo acepta *direcciones* de longitud ≤ 1. Cada tick concede 1 ficha de movimiento (máx. 6) y cada comando gasta una: enviar más rápido **no** mueve más rápido. Cola limitada a 10 y detección estadística si el ritmo supera el 130 % del real. | `game_server.gd` → `on_input`, `_simulate`, `_update_anticheat` |
| 2 | **Teletransporte / posición falsa** | El cliente **nunca** envía posiciones. El servidor calcula cada paso y el cliente acepta siempre la corrección. | `movement.gd`, `_simulate`, `game_client.gd` → `on_snapshot` |
| 3 | **Atravesar murallas (noclip)** | Colisiones resueltas en el servidor: anillo de muralla con huecos solo en portones destruidos o propios. | `movement.gd` → `resolve`, `in_open_gate` |
| 4 | **Hack de daño o de enfriamientos** | Daño, enfriamientos, GCD y efectos salen de la tabla `GameData.ABILITIES` en el servidor. El cliente solo envía `slot` y `target_id`. | `on_ability`, `_ability_attack` |
| 5 | **Alcance infinito / disparar a través de muros** | Distancia validada con 1 m de tolerancia y línea de visión contra la muralla. | `_ability_attack`, `_line_of_sight` |
| 6 | **ESP / wallhack** | Área de interés de 75 m; los enemigos en sigilo **no se envían**; activar el sigilo no se anuncia al enemigo. Lo que no llega al cliente no se puede leer de su memoria. | `_send_snapshots`, `_visible_to`, `_broadcast_fx` |
| 7 | **Suplantar a otro jugador en un RPC** | El emisor sale siempre de `multiplayer.get_remote_sender_id()`, nunca del contenido del paquete. | `network.gd` |
| 8 | **Cliente llamando funciones de servidor o hablando con otro cliente** | RPC servidor→cliente con `@rpc("authority")`; `server_relay = false`. | `network.gd`, `GameServer.start` |
| 9 | **Deserialización de objetos (ejecución remota de código)** | `allow_object_decoding = false`; la auth usa JSON con límite de tamaño, nunca `bytes_to_var_with_objects`. | `GameServer.start`, `Protocol.parse_json_bytes` |
| 10 | **Paquetes malformados** (tipos erróneos, NaN/Inf, tamaños) | Parámetros RPC sin tipo a propósito + `typeof()`, `is_finite()` y tamaños máximos. Cada anomalía suma puntos de infracción, que decaen 0,5/s; con 12 hay expulsión. | `on_input`, `on_ability`, `on_chat`, `_violation` |
| 11 | **Flood / DoS ligero** | *Token bucket* por tipo de mensaje (input 60/s, habilidades 5/s, chat 1 cada 2 s), máx. 4 conexiones por IP, timeout de auth de 6 s y de `ready` de 10 s. | `rate_limiter.gd`, `on_peer_authenticating` |
| 12 | **Fuerza bruta de la contraseña** | Desafío-respuesta (la contraseña nunca viaja), comparación en tiempo constante y bloqueo de la IP 5 min tras 5 fallos en 60 s. | `_on_auth_data`, `_register_failure`, `Protocol.constant_time_equals` |
| 13 | **Repetición (replay) de la autenticación** | Nonce aleatorio (`Crypto.generate_random_bytes`) distinto en cada conexión. | `on_peer_authenticating` |
| 14 | **Inyección en el chat** (BBCode, texto bidireccional, caracteres invisibles) | El servidor elimina caracteres de control, *zero-width* y *overrides* bidi, y limita la longitud. El cliente pinta con `add_text()`, que no interpreta BBCode. Chat solo de reino. | `Protocol.sanitize_chat`, `Hud.add_chat`, `on_chat` |
| 15 | **Suplantación de nombre** | Regex `[A-Za-z0-9_ÁÉÍÓÚÜÑáéíóúüñ]{3,16}` y nombres únicos sin distinguir mayúsculas. | `Protocol.sanitize_name`, `_name_taken` |
| 16 | **Spawn camping** | Santuario invulnerable para los propios y letal para los intrusos. | `_simulate`, `_in_own_sanctuary` |
| 17 | **Acumular jugadores en un reino** | Margen de equilibrio configurable (`realm_balance_margin`). | `_realm_has_room` |
| 18 | **Ventaja o exposición del anfitrión** | "Hospedar y jugar" lanza el servidor como **otro proceso**: el anfitrión es un cliente más. El script de firewall abre solo UDP y solo en redes privadas. La contraseña no se guarda en `client.cfg`. | `main.gd`, `tools/abrir_puerto_firewall.ps1` |
| 19 | **Versiones mezcladas** | `Protocol.VERSION` en el handshake: cliente y servidor rechazan versiones distintas. | `_on_auth_data`, `GameClient._on_auth_data` |

### Registro de seguridad
El servidor escribe en consola (y en el log de Godot, `%APPDATA%\Godot\app_userdata\Velkaris\logs`)
cada infracción con nombre, id, IP y motivo: `[ANTICHEAT]`, `[KICK]` y `[SEGURIDAD]`.

---

## 4. Limitaciones conocidas y siguientes pasos

| Limitación | Impacto | Siguiente paso |
|---|---|---|
| Tráfico ENet **sin cifrar** | Posiciones y chat viajan en claro (la contraseña no) | Hoy: VPN (Tailscale, ZeroTier, WireGuard). Después: DTLS de ENet (`ENetConnection.dtls_server_setup` / `dtls_client_setup` con `TLSOptions`) |
| Sin cuentas persistentes | Cualquiera con la contraseña elige nombre libre | Servicio de cuentas externo con Argon2id y tokens firmados verificados en el handshake |
| El RPC se decodifica antes de validarse | Un paquete enorme consume memoria antes de rechazarse | Ya mitigado con rate limit + expulsión. Siguiente: proxy UDP o límite de tamaño en la capa de transporte |
| DoS volumétrico | Puede tumbar la conexión del anfitrión | No se resuelve en la aplicación: VPS con protección DDoS o red privada |
| Sin anticheat en el cliente | Bots de entrada o aimbots no se detectan | Todo lo crítico ya es del servidor. Añadir heurísticas (tiempos de reacción, precisión) y revisión de replays |
| Un proceso = una zona | ~32-64 jugadores por proceso | Varias instancias por frente + matchmaking |
| Sin persistencia | La campaña vive en memoria | Base de datos (SQLite/PostgreSQL) para campaña, rangos y estadísticas |

---

## 5. Checklist de pruebas de seguridad

1. Modificar el cliente para enviar `move = Vector2(10, 0)` → el servidor recorta a longitud 1 y registra `[ANTICHEAT]`.
2. Enviar 60 comandos por segundo en lugar de 30 → la velocidad no cambia; aparecen avisos de cola desbordada y, a los 5 s, de ritmo anómalo.
3. Enviar `NaN` en el yaw → expulsión tras pocas repeticiones.
4. Llamar `s2c_snapshot` desde un cliente → Godot la rechaza (`authority`).
5. Conectar 5 veces con contraseña errónea → la IP queda bloqueada 5 minutos.
6. Escribir `[url=http://x]clic[/url]` en el chat → se ve el texto literal.
7. Activar *Velo de Bruma* y comprobar con un segundo cliente enemigo a más de 4 m que tu entidad desaparece de sus snapshots.
