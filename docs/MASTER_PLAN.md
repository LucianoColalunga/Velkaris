# Velkaris: auditoría técnica y Development Master Plan

**Versión auditada:** v0.1.0 (commit `a6f90d8`) · **Fecha:** 2026-10-06 · **Motor:** Godot 4.3 (Compatibility)

---

## 0. Resumen ejecutivo

- **La base técnica es sólida y está verificada:** el servidor es autoritativo de verdad. Movimiento, colisiones, combate, capturas, puntuación, reaparición y anticheat funcionan contra un servidor real (pruebas automatizadas en la sección 1).
- **El problema principal es el juego, no la técnica:** el combate no se siente (golpes instantáneos sin animación, sonido ni impacto), el RvR no da información para decidir (no hay minimapa) y el asedio se reduce a pegarle a una caja que no se defiende.
- **No hay audio ni assets:** 0 sonidos, 0 modelos y 0 texturas. Todo son primitivas, así que hay mucho margen visual sin riesgo de rendimiento.
- **Rendimiento muy holgado (medido):** 157 MB de RAM en el cliente, 68 MB en el servidor, unos 70 draw calls y 60 FPS. Hay presupuesto de sobra para assets reales.
- **Para una demo pública faltan:** reconexión, endurecer el servidor ante abusos de conexión, un servidor accesible por Internet, minimapa, combate con *feel*, audio mínimo y una web.
- **Recomendación:** primero **robustez y QA** (sprint 1); después **combate → RvR → asedio → mapa**, en el orden pedido. Los assets entran desde packs **CC0** gratuitos (KayKit, Kenney, Quaternius) antes de pagar por cualquier asset.

---

## 1. Método y evidencia

1. Revisión completa de los 14 scripts (~3000 líneas de GDScript), las escenas, la configuración y el tooling.
2. Pruebas reales con Godot 4.3:

| Prueba | Qué comprueba | Resultado |
|---|---|---|
| `tests/smoke_bot` (sin ventana, con ventana y contra `VelkarisServer.exe` compilado) | Auth con contraseña, predicción, muralla, daño a portón | ✅ OK: muralla a 19,50 m; portón de 4000 a 2680 (3 × 440) |
| `tests/qa_bot` (3 procesos simultáneos) | Captura, disputa, combate, muerte, reaparición, puntos, speedhack, NaN | ✅ OK (detalle abajo) |
| Medición de rendimiento con ventana (GTX 1650, 1280×720) | FPS, draw calls, RAM y CPU | 60 FPS (V-Sync) · 68-73 draw calls · ~28 000 primitivas · cliente 157 MB · servidor 68 MB · CPU del servidor < 1 % |

**Detalle de `qa_bot`:**
- **Captura:** la atalaya se captura en 11,8 s.
- **Disputa:** con dos reinos dentro, el punto queda congelado.
- **Combate:** un Quebrantamuros abate a un Cantor que se cura en ~11-15 s y termina con 734/1400 de vida.
- **Puntuación:** pasa de `[1,0,0]` a `[8,0,0]` (atalaya + derribo).
- **Reaparición:** a los 5,9 s, en el santuario y con la vida llena.
- **Speedhack:** enviando el doble de comandos, el servidor movió al tramposo a 7,47 m/s frente a 6 legales (ráfaga acotada, no velocidad sostenida).
- **NaN:** tres paquetes con NaN acaban en expulsión.

---

## 2. Qué está realmente implementado

Leyenda: ✅ verificado con pruebas · 🟡 implementado pero sin verificar · 🟠 parcial · ❌ no existe

| Área | Sistema | Estado | Nota |
|---|---|---|---|
| Gameplay | Movimiento WASD + cámara MMO | ✅ | |
| | Colisiones (muralla, pilares, límite del mapa) | ✅ | Árboles y rocas **sin** colisión |
| | Combate cuerpo a cuerpo y a distancia | ✅ | Instantáneo (hitscan), sin animación |
| | Curación, Baluarte | 🟡 | El bot los usó, pero no se midió su efecto |
| | Embestida (dash) | 🟡 | El cliente no la predice: corrección visual |
| | Velo de Bruma (sigilo) | 🟡 | El filtrado de snapshots está implementado |
| | Carga de Zapa, Sello de Resonancia | 🟡 | |
| | Atalayas: captura y disputa | ✅ | |
| | Atalayas: neutralización por otro reino | 🟡 | La lógica existe |
| | Portones: daño | ✅ | |
| | Portones: destrucción y paso por el hueco | 🟡 | |
| | Bastión: captura y reconstrucción de portones | 🟡 | |
| | Puntuación (atalayas y derribos) | ✅ | |
| | Victoria a 300 y reinicio | 🟡 | Reinicio instantáneo, sin pantalla de resultados |
| | Reaparición | ✅ | |
| | Guardia del santuario | 🟡 | |
| Red | Servidor autoritativo, handshake de 3 fases | ✅ | |
| | Predicción y reconciliación | ✅ | |
| | Interpolación | 🟠 | Usa el reloj local de recepción (ver N1) |
| | Área de interés (75 m) | 🟡 | |
| | Reconexión / período de gracia | ❌ | |
| | Hospedar y jugar (lanza un servidor local) | 🟡 | |
| Seguridad | Validación de tipos, NaN y tamaños; rate limit | ✅ | |
| | Anti-speedhack | ✅ | Ráfaga residual de ~3 m |
| | Contraseña por desafío-respuesta, bloqueo de IP | 🟡 | |
| | Cifrado (DTLS) | ❌ | |
| UX | Menú, HUD, chat de reino, ayuda F1 | ✅ / 🟡 | |
| | Minimapa, mapa, marcadores | ❌ | |
| | Barra de progreso de captura | ❌ | El estado solo aparece en texto |
| | Opciones (volumen, teclas, sensibilidad, calidad) | 🟠 | Solo hay sombras sí/no |
| Contenido | Modelos 3D, texturas, animaciones | ❌ | 100 % primitivas |
| | Audio | ❌ | 0 `AudioStreamPlayer` |
| | Progresión, persistencia, cuentas | ❌ | Correcto por ahora: no es prioridad |
| Ingeniería | Build local (cliente, servidor Windows y Linux) | ✅ | Icono vía rcedit |
| | CI (GitHub Actions) | 🟠 | Escrito, pero **bloqueado por facturación de la cuenta** |
| | Tests | 🟠 | 2 bots de integración; sin tests unitarios |

---

## 3. Diagnóstico por área

### Combate
- **C1. Sin *game feel*:** el daño es instantáneo, sin anticipación, sin reacción del objetivo, sin sonido y con VFX mínimos (esferas y cajas). Es el problema más grande de diversión.
- **C2. Poca profundidad:** 3 habilidades por clase, sin recurso ni ataque básico. La rotación se reduce a "pulsar 1 y usar 2 y 3 cuando haya enfriamiento".
- **C3. Selección de objetivo limitada:** solo Tab o autoobjetivo. No se puede elegir con el ratón porque los avatares no tienen colisionador.
- **C4. Contrajuego inexistente:** el sigilo no se puede revelar, la Carga de Zapa no se puede desactivar y no hay interrupciones.
- **C5. Embestida sin predicción:** el personaje "salta" visualmente. Además usa la última dirección de movimiento, no la de la cámara.
- **C6. La curación ignora la línea de visión** y atraviesa la muralla.
- **C7. Sin hoja de balance:** no hay una tabla formal de DPS, vida efectiva y tiempo para matar por enfrentamiento.

### RvR
- **R1. Sin minimapa ni avisos de "atalaya bajo ataque":** el jugador no puede decidir dónde ir. Es crítico para un RvR.
- **R2. Atalayas sin valor más allá de los puntos:** no tienen defensa, protección tras la captura ni beneficios (por ejemplo, reaparición avanzada). Se intercambian sin coste.
- **R3. Sin mecánica anti "2 contra 1"** ni ayuda al reino que va perdiendo, algo clave con tres facciones.
- **R4. Final de campaña abrupto:** sin pantalla de resultados, estadísticas ni intermisión.
- **R5. No se ve la población de cada reino.**

### Asedio
- **S1. El defensor no tiene ventaja:** no hay adarve, no puede disparar desde la muralla (la línea de visión bloquea a ambos lados) y no puede reparar.
- **S2. Portones demasiado frágiles:** un solo Quebrantamuros derriba uno en ~11 s (440 por golpe contra 4000 de vida).
- **S3. Sin armas ni roles de asedio** más allá del multiplicador de daño a estructuras.

### Mapa
- **M1. Plano, circular y simétrico:** sin elevación ni cuellos de botella (salvo los portones), así que hay pocas decisiones de ruta.
- **M2. Árboles y rocas decorativos:** se atraviesan, no dan cobertura y la línea de visión solo considera la muralla.
- **M3. El obelisco del santuario tapa la cámara al aparecer** (visto en las capturas).

### Visual
- **V1.** Personajes cápsula: la clase se reconoce por un "sombrero" primitivo y el reino solo por el color. No hay armas ni animación.
- **V2.** Mundo sin texturas ni identidad por reino: los tercios del mapa son iguales.
- **V3.** VFX mínimos, sin partículas ni destello de impacto en el objetivo.
- **V4.** Interfaz con el tema por defecto de Godot y barras de vida en ASCII sobre las cabezas.

### Audio
- **A1.** No existe.

### Networking
- **N1. Interpolación con el reloj local de recepción:** con jitter real de Internet produce tirones. Debe usar el tick del servidor y un búfer adaptativo.
- **N2. Snapshots completos sin cuantizar ni deltas:** sirve hasta ~32-64 jugadores; no escala más.
- **N3. Sin reconexión ni período de gracia,** con el timeout de ENet por defecto: un microcorte = perder el personaje, y los "fantasmas" pueden tardar hasta ~30 s en irse.
- **N4.** "Hospedar y jugar" no está verificado. No hay lista ni descubrimiento de servidores.

### Seguridad
- **Verificado:** límite de velocidad, expulsión por NaN, rechazo de paquetes malformados, RPC con `authority`, `server_relay` y decodificación de objetos desactivados.
- **SEC1. Tráfico sin cifrar:** quien capture el desafío de contraseña puede intentar adivinarla offline. Mitigación: contraseñas fuertes ahora y DTLS después.
- **SEC2. Conexiones a medio autenticar:** pueden ocupar plazas durante unos segundos (riesgo de denegación de entrada en un servidor público).
- **SEC3. Logs del anticheat sin límite:** una línea por infracción. Riesgo de inundación de logs.
- **SEC4. Ráfaga residual del speedhack (~3 m)** por la cola y las fichas acumuladas.
- **SEC5.** El RPC se decodifica entero antes de validarse.
- **SEC6.** Los avisos de "fuera de alcance" revelan enemigos fuera del área de interés (bajo).
- **SEC7.** Los bloqueos de IP viven en memoria (bajo).

### UX
- **U1.** Sin minimapa, brújula ni marcadores de objetivo en pantalla.
- **U2.** Sin barra de captura al estar en el círculo.
- **U3.** Feedback de daño básico: sin indicador direccional ni resumen de muerte.
- **U4.** Sin menú de opciones.
- **U5.** Escape no sale del chat; los derribos se mezclan con el chat.
- **U6.** Sin tutorial.

### Rendimiento
- **Medido:** muy por debajo de los límites (ver sección 1).
- **Riesgos futuros:** sin LOD, sin `visibility_range` ni culling por distancia, materiales únicos por avatar y un `Label3D` por jugador. Hay que medir en una GPU integrada (Intel UHD), que es el objetivo real de gama baja.
- **Servidor:** el área de interés es O(n²) por snapshot; está bien hasta ~64 jugadores.

### Arquitectura
- **AR1.** `game_server.gd` (~880 líneas) mezcla auth, simulación, combate, objetivos, snapshots y anticheat. Hay que dividirlo en módulos **moviendo código, sin reescribirlo**, antes de agregar mecánicas.
- **AR2.** `game_client.gd` (~530 líneas) mezcla red, predicción, selección de objetivo y FX.
- **AR3.** Todo se construye por código, sin escenas. Los assets reales van a necesitar `PackedScene` para avatares y estructuras.
- **AR4.** Los datos de balance están en diccionarios `const`. Moverlos a recursos `.tres` permite balancear sin tocar código.
- **AR5.** Sin framework de tests unitarios ni CI activo.

---

## 4. Assets: qué reemplazar primero y de dónde

| Prioridad | Elemento | Fuente recomendada (gratuita) | Licencia | Notas de uso |
|---|---|---|---|---|
| 1 | Personajes (siempre en pantalla) | **KayKit Character Pack: Adventurers** (Kay Lousberg). Barbarian/Knight → Quebrantamuros, Mage → Cantor, Rogue → Zapador | CC0 | GLTF con esqueleto, compatible con Godot. Tinte por reino |
| 2 | Animaciones (idle, correr, ataque, impacto, muerte) | Incluidas en KayKit; **Quaternius Universal Animación Library** como complemento | CC0 | `AnimaciónTree` controlado por velocidad y flags del snapshot |
| 3 | Armas | Incluidas en KayKit | CC0 | |
| 4 | Bastión, murallas, portones | **Kenney Castle Kit** | CC0 | Mantener la colisión analítica actual; solo cambia la malla |
| 5 | Atalayas | Kenney Castle Kit + cristal propio (shader emisivo en Godot, sin modelo) | CC0 | |
| 6 | Identidad de reino | 3 emblemas propios (Krita o Inkscape) + estandartes + paletas | Propia | Hacer a mano: es identidad, no debe salir de un pack |
| 7 | Props | Kenney / KayKit | CC0 | |
| 8 | Vegetación y rocas | **Quaternius Stylized Nature MegaKit** o Kenney Nature Kit | CC0 | Siguen en `MultiMesh` |

**Se reutiliza:**
- El icono (base del logo) y la paleta de colores de los reinos.
- El pipeline de `MultiMesh`.
- La colisión analítica de `Movement`: las mallas nuevas son solo visuales.
- La disposición del mapa.

**Audio:**
- **Kenney** (Impact Sounds, RPG Audio, Interface Sounds; CC0).
- Bundles **Sonniss GameAudioGDC** (libres de regalías para usar en juegos).
- **Freesound** filtrado por CC0.
- **Música:** OpenGameArt CC0, o CC-BY con créditos en un archivo `CREDITS.md`.
- Objetivo: ~25 sonidos y 2 pistas, no más.

**Herramientas gratuitas:** Blender, Krita/Inkscape, Audacity, el profiler y los monitores de Godot, **gdUnit4** (tests, MIT), **clumsy** (simular latencia y pérdida en Windows), **playit.gg** (túnel UDP gratis), Tailscale.

**Assets a medida:** solo para piezas únicas que ningún pack CC0 cubra, y primero como prototipo. Hoy no hace falta.

> Evitar subir al repo público archivos de Mixamo u otras fuentes que prohíben redistribuir los assets en bruto.

---

## 5. Deployment: qué va a Vercel y qué no

**Vercel no puede ejecutar el servidor de Godot:** sus funciones son efímeras, con tiempo limitado y sin UDP. Sí sirve para:

| En Vercel | Cómo |
|---|---|
| Landing / página oficial | Sitio estático |
| Descarga | Enlace a GitHub Releases (evita gastar ancho de banda de Vercel) |
| Estado del servidor | El servidor de Godot envía un *heartbeat* HTTPS firmado (HMAC) cada 30 s a una función de Vercel. Se guarda en un KV gratuito (Upstash Redis free tier) |
| Rankings y estadísticas | El servidor envía el resumen de cada campaña firmado; la web lo muestra |
| Documentación y lore | Páginas estáticas |

> El plan Hobby de Vercel es para uso no comercial: sirve para una beta gratuita.

**El servidor de Godot necesita un proceso permanente con UDP abierto (7777).** Opciones, de gratis a barato:

1. **Gratis ya:** tu PC + **playit.gg** (túnel UDP sin abrir puertos). Ideal para las primeras pruebas con desconocidos. Contra: la PC tiene que estar encendida.
2. **Gratis permanente:** **Oracle Cloud Always Free**. VM ARM (hasta 4 núcleos y 24 GB) en São Paulo o Santiago, con baja latencia para LATAM. Pide tarjeta para verificar, pero no cobra. Hay que exportar el servidor para Linux ARM64 (plantilla incluida en Godot). Riesgo: a veces no hay capacidad ARM disponible.
3. **Gratis con latencia alta:** Google Cloud e2-micro (solo regiones de EE. UU.).
4. **Bajo costo (requiere tu autorización):** VPS de ~5-6 USD/mes en São Paulo.

**WebSocket no hace falta:** el juego es de escritorio, así que ENet/UDP es lo correcto.

---

## 6. Qué falta para una primera demo pública

- [ ] Servidor público estable (playit.gg u Oracle Free) con reinicio automático y logs.
- [ ] Reconexión con período de gracia y timeouts de red ajustados.
- [ ] Endurecer las conexiones pendientes y limitar los logs (SEC2, SEC3).
- [ ] Combate con *feel* mínimo: animaciones, sonidos de impacto y VFX legibles.
- [ ] Minimapa, barra de captura y avisos de ataque.
- [ ] Personajes KayKit y castillo Kenney (al menos lo que se ve siempre).
- [ ] Audio mínimo (~25 sonidos y 2 pistas).
- [ ] Opciones básicas (volumen, sensibilidad, calidad).
- [ ] QA automatizada de **todas** las habilidades y del ciclo completo de la campaña.
- [ ] Prueba con 6-10 personas reales y recolección de logs.
- [ ] Web en Vercel con descarga y estado del servidor.
- [ ] Release descargable (requiere resolver la facturación de GitHub o publicarla a mano).

---

## 7. VELKARIS DEVELOPMENT MASTER PLAN

**Formato de cada tarea:** Problema → Solución → Área → Herramienta → Costo → Impacto → Riesgo.
"Costo" es el dinero (todo es gratis salvo que se indique) más una estimación de esfuerzo.

### Acciones del propietario (bloquean o arriesgan; solo las puede hacer el dueño de la cuenta)

| # | Acción | Por qué |
|---|---|---|
| P-2 | Borrar el `.git` que quedó en la carpeta de usuario de Windows | Esa carpeta sigue siendo un repo con `origin` = Velkaris: un `git add .` ahí podría subir archivos privados |
| P-3 | Resolver el bloqueo de facturación de GitHub | Sin eso no funcionan el CI ni las Releases automáticas |

### CRÍTICO

**C-1. QA automatizada de todos los sistemas**
- **Problema:** la mitad de las mecánicas (sigilo, embestida, zapa, Bastión, victoria, guardia, chat, hospedar) no están verificadas. Cualquier cambio puede romperlas sin que nadie lo note.
- **Solución:** ampliar `tests/qa_bot` con un escenario por sistema y un script `tests/run_all` que levante el servidor y los bots y devuelva OK/FALLO. Correrlo después de cada cambio.
- **Área:** QA · **Herramienta:** Godot headless + PowerShell · **Costo:** gratis, ~1,5 días · **Impacto:** muy alto (es la red de seguridad de todo lo demás) · **Riesgo:** bajo.

**C-2. Reconexión y timeouts**
- **Problema:** con micro-cortes de Internet se pierde el personaje, y los fantasmas tardan hasta ~30 s en irse.
- **Solución:**
  - Timeouts de ENet ajustados (~10 s).
  - Token de sesión aleatorio de 128 bits entregado en la bienvenida.
  - Si te desconectás, el servidor conserva tu personaje 45 s y el reingreso con el token lo recupera (posición, vida, enfriamientos).
- **Área:** Programación de red · **Herramienta:** Godot · **Costo:** gratis, ~1 día · **Impacto:** alto · **Riesgo:** medio (seguridad del token: un solo uso, con caducidad).

**C-3. Endurecer conexiones y logs**
- **Problema:** conexiones a medio autenticar pueden ocupar plazas (SEC2) y los logs del anticheat son inundables (SEC3).
- **Solución:** tope global de conexiones pendientes, auth en ~3 s y logs agregados por jugador (un resumen cada 5 s).
- **Área:** Seguridad · **Herramienta:** Godot · **Costo:** gratis, ~0,5 días · **Impacto:** alto para un servidor público · **Riesgo:** bajo.

**C-4. Cerrar la ráfaga de speedhack y medir con red degradada**
- **Problema:** queda una ventaja residual de ~3 m (SEC4). Además, los umbrales nunca se probaron con latencia y pérdida reales.
- **Solución:** descartar el atraso en vez de ejecutarlo, ajustar cola y fichas, y validar con clumsy (150 ms, 5 % de pérdida, jitter) que un jugador legítimo no reciba falsos positivos.
- **Área:** Programación + QA · **Herramienta:** Godot, clumsy · **Costo:** gratis, ~0,5 días · **Impacto:** alto · **Riesgo:** medio (falsos positivos si se ajusta de más).

**C-5. Interpolación con el reloj del servidor**
- **Problema:** usar la hora local de recepción provoca tirones en Internet (N1).
- **Solución:** sellar los snapshots con el tick del servidor y usar un búfer de interpolación adaptativo al jitter medido.
- **Área:** Programación de red · **Herramienta:** Godot · **Costo:** gratis, ~0,5-1 día · **Impacto:** alto en la sensación online · **Riesgo:** medio.

### ALTA PRIORIDAD (en el orden: combate → RvR → asedio → mapa → identidad → personajes → audio → demo)

**A-1. Modularizar servidor y cliente (sin reescribir)**
- **Problema:** archivos monolíticos (AR1, AR2) que frenan cualquier mejora.
- **Solución:**
  - Servidor: extraer `AuthService`, `CombatSystem`, `ObjectiveSystem`, `SnapshotBuilder` y `AntiCheat` moviendo las funciones existentes.
  - Cliente: separar red y predicción de la presentación.
  - Mismo protocolo; las pruebas de C-1 tienen que seguir en verde.
- **Área:** Programación · **Costo:** gratis, ~1 día · **Impacto:** alto (habilita todo lo que sigue) · **Riesgo:** bajo con C-1 hecho.

**A-2. *Game feel* del combate**
- **Problema:** C1.
- **Solución:**
  - Anticipación corta en las habilidades fuertes. El servidor valida el tiempo de lanzamiento; el cliente anima al instante.
  - Destello y pequeño retroceso en el objetivo, empuje leve en Golpe Sísmico (decidido por el servidor).
  - Proyectil visible para el Rayo y círculo de aviso para la Carga de Zapa.
  - Mejores números de daño y vibración de cámara leve.
- **Área:** Gameplay + Animación + Audio · **Herramienta:** Godot (`CPUParticles3D`, compatible con gama baja) · **Costo:** gratis, ~3-5 días · **Impacto:** muy alto · **Riesgo:** medio (las anticipaciones tienen que convivir con la latencia).

**A-3. Profundidad del combate (sin inflar)**
- **Problema:** C2, C4, C6, C7.
- **Solución:**
  - Un recurso por clase con identidad: Furia, Resonancia, Bruma.
  - Un ataque básico.
  - Una habilidad más por clase: 4 en total, no 30.
  - Contrajuego: el Sello del Cantor revela el sigilo cerca, una Carga de Zapa se desactiva interactuando 1,5 s, y el Golpe Sísmico interrumpe lanzamientos.
  - Línea de visión también para la curación.
  - Hoja de balance de DPS, vida efectiva y tiempo para matar en un recurso `.tres`.
- **Área:** Gameplay · **Costo:** gratis, ~4-6 días · **Impacto:** alto · **Riesgo:** medio-alto (balance; hay que iterar con playtests).

**A-4. Información de batalla: minimapa y avisos**
- **Problema:** R1, R5, U1, U2.
- **Solución:**
  - Minimapa y mapa grande (M) con atalayas, portones, aliados y peleas en curso.
  - Avisos: "Atalaya del Alba bajo ataque", "Portón Norte al 50 %".
  - Barra de captura en pantalla y población por reino.
  - El servidor solo envía información a la que el reino debería tener acceso.
- **Área:** UX + Diseño de niveles · **Costo:** gratis, ~2-3 días · **Impacto:** muy alto · **Riesgo:** bajo.

**A-5. Atalayas con valor estratégico**
- **Problema:** R2, R3.
- **Solución:**
  - 30 s de protección tras la captura.
  - Reaparición avanzada en atalayas propias.
  - Líneas de suministro: solo puedes atacar el portón que mira a una atalaya que controles.
  - Ayuda al reino que va último: captura un poco más rápida.
- **Área:** Gameplay + Narrativa · **Costo:** gratis, ~2-3 días · **Impacto:** alto (el RvR gana decisiones) · **Riesgo:** medio.

**A-6. Asedio de verdad**
- **Problema:** S1-S3.
- **Solución:**
  - Portones con vida escalada y fases visuales de daño.
  - Los defensores pueden reparar.
  - Plataformas de defensa detrás de la muralla con línea de visión elevada y bonus de daño, como zonas 2,5D dentro del modelo actual (sin motor de físicas).
  - Un ariete ligero (arma de asedio que empujan 2 o más jugadores, muy eficaz contra portones y vulnerable).
- **Área:** Gameplay + Diseño de niveles · **Costo:** gratis, ~4-6 días · **Impacto:** muy alto · **Riesgo:** alto (toca el movimiento compartido y la línea de visión; requiere C-1).

**A-7. Mapa con decisiones**
- **Problema:** M1-M3.
- **Solución:**
  - Obstáculos grandes con colisión y bloqueo de visión (bosques densos, formaciones rocosas) como círculos o cajas en `GameData`.
  - 2-3 rutas por carril (cubierta frente a camino rápido).
  - Un río con vados como cuello de botella.
  - Reubicar el obelisco del santuario.
- **Área:** Diseño de niveles · **Herramienta:** Godot (`CSG` para bocetar) · **Costo:** gratis, ~3-5 días · **Impacto:** alto · **Riesgo:** medio.

**A-8. Identidad visual por reino (fase barata)**
- **Problema:** V2, V4.
- **Solución:**
  - Terreno con un material distinto por tercio: ceniza volcánica (Brasalta), manglar (Umbravel), roca alta y nieve (Céfira).
  - Emblemas y estandartes que cambian al capturar.
  - Interfaz con tema propio y colores del reino del jugador.
- **Área:** Arte 3D + Narrativa · **Herramienta:** Krita, Inkscape, Godot · **Costo:** gratis, ~2-4 días · **Impacto:** alto · **Riesgo:** bajo.

**A-9. Personajes, armas y animaciones**
- **Problema:** V1, AR3.
- **Solución:**
  - Integrar KayKit Adventurers (CC0) y el castillo de Kenney.
  - `PlayerAvatar` pasa a instanciar una escena.
  - `AnimaciónTree` controlado por el snapshot.
  - Tinte por reino y LOD básico.
- **Área:** Arte 3D + Animación · **Herramienta:** Blender, Godot · **Costo:** gratis, ~3-5 días · **Impacto:** muy alto · **Riesgo:** medio (presupuesto de polígonos: medir en GPU integrada).

**A-10. Audio mínimo viable**
- **Problema:** A1.
- **Solución:** ~25 efectos CC0 (pasos, golpes, rayo, curación, sigilo, explosión, portón, captura, interfaz, muerte), 1 ambiente y 1 tema de batalla. Pool de `AudioStreamPlayer3D` con límite de voces. Volúmenes en las opciones.
- **Área:** Audio · **Herramienta:** Audacity · **Costo:** gratis, ~2 días · **Impacto:** alto · **Riesgo:** bajo.

**A-11. Servidor público de pruebas**
- **Problema:** nadie fuera de tu red puede jugar.
- **Solución:** fase 1 con playit.gg desde tu PC; fase 2 con Oracle Cloud Always Free (export para Linux ARM64, servicio systemd con reinicio automático y logs rotados).
- **Área:** Infraestructura · **Costo:** gratis (Oracle pide tarjeta para verificar), ~1 día · **Impacto:** alto · **Riesgo:** medio (disponibilidad de Oracle).

**A-12. Web oficial en Vercel**
- **Problema:** no hay presencia pública.
- **Solución:**
  - Landing con estética de MMORPG: logo, tres reinos, gameplay, capturas, beta.
  - Botón de descarga a GitHub Releases.
  - Estado del servidor por heartbeat firmado.
- **Área:** Narrativa + Web · **Herramienta:** HTML/CSS estático o Next.js en Vercel Hobby · **Costo:** gratis, ~2-3 días · **Impacto:** alto para la beta · **Riesgo:** bajo.

**A-13. Opciones y onboarding**
- **Problema:** U4-U6.
- **Solución:** menú de opciones (volumen, sensibilidad, teclas, calidad, FOV), tutorial de 60 s con los objetivos, Escape cierra el chat y el registro de derribos se separa del chat.
- **Área:** UX · **Costo:** gratis, ~2 días · **Impacto:** medio-alto · **Riesgo:** bajo.

### MEDIA PRIORIDAD

| # | Problema | Solución | Área | Herramienta | Costo | Impacto | Riesgo |
|---|---|---|---|---|---|---|---|
| M-1 | Snapshots que no escalan (N2) | Cuantización + `PackedFloat32Array` + deltas por entidad | Programación | Godot | Gratis, 1-2 días | Alto con >32 jugadores | Medio |
| M-2 | Tráfico en claro (SEC1) | DTLS en ENet con certificado propio fijado en el cliente | Programación | Godot `TLSOptions` | Gratis, 1-2 días | Medio | Medio |
| M-3 | Balance metido en el código (AR4) | Recursos `.tres` para clases y habilidades | Gameplay | Godot | Gratis, 1 día | Medio | Bajo |
| M-4 | Final de campaña abrupto (R4) | Pantalla de resultados, estadísticas, MVP, intermisión de 30 s | Gameplay + UX | Godot | Gratis, 1-2 días | Medio | Bajo |
| M-5 | Feedback de daño pobre (U3) | Indicador direccional, resumen de muerte, registro de derribos | UX | Godot | Gratis, 1 día | Medio | Bajo |
| M-6 | Rendimiento al crecer el contenido | LOD, `visibility_range`, impostores para árboles, presupuesto (draw calls, VRAM) medido en GPU integrada | Optimization | Godot profiler | Gratis, 1-2 días | Alto a futuro | Bajo |
| M-7 | Sin tests unitarios ni CI (AR5) | gdUnit4 para `Movement`, `Protocol` y capturas; CI con los bots headless cuando se resuelva la facturación | QA | gdUnit4, Actions | Gratis, 1-2 días | Medio | Bajo |
| M-8 | Sin rankings | Estadísticas firmadas del servidor → función de Vercel → Upstash Redis | Web | Vercel, Upstash free | Gratis, 1-2 días | Medio | Bajo |
| M-9 | Ventajas de información menores (SEC6, SEC7) | Mensajes de alcance uniformes; persistir bloqueos en disco | Programación | Godot | Gratis, 0,5 días | Bajo | Bajo |

### BAJA PRIORIDAD

| # | Idea | Por qué esperar | Área |
|---|---|---|---|
| B-1 | Progresión (rangos de reino, cosméticos) | Solo cuando el núcleo del juego sea divertido | Gameplay |
| B-2 | Reliquias "Corazones de Esquirla" | Depende de que el RvR básico esté pulido | Gameplay + Narrativa |
| B-3 | Cuentas persistentes (Argon2id, servicio externo) | Hace falta recién con progresión | Programación |
| B-4 | Varias instancias o frentes y matchmaking | Recién con más de 64 jugadores | Programación |
| B-5 | Trailer y capturas oficiales | Después de A-8, A-9 y A-10 | Narrativa + Arte 3D |
| B-6 | Firma de código (quitar el aviso de SmartScreen) | Tiene costo; posponer hasta la beta abierta | Programación |
| B-7 | Localización al inglés | Para la beta abierta | Narrativa |
| B-8 | Cliente web (WebSocket) | No recomendado: peor rendimiento y más superficie de ataque | — |

### Propuesta de sprints

| Sprint | Contenido | Resultado visible |
|---|---|---|
| 1 | C-1 → C-5 + A-1 | Base robusta para Internet y una red de pruebas completa |
| 2 | A-2 + A-3 | El combate se siente y tiene decisiones |
| 3 | A-4 + A-5 | El RvR tiene información y estrategia |
| 4 | A-6 + A-7 | Asedio y mapa con profundidad |
| 5 | A-8 + A-9 + A-10 | Prototipo visual: cada reino se ve y suena distinto |
| 6 | A-11 + A-12 + A-13 + QA con jugadores reales | **Primera demo pública (alpha cerrada)** |
