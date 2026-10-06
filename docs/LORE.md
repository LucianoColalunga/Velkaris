# Lore de Velkaris

## El mundo: Velkaris y la Fractura de Ilun

Hace trescientos años la luna de Velkaris, **Ilun**, se resquebrajó en una sola noche que los
cronistas llaman **la Fractura**. Durante un año llovieron **esquirlas lunares**: cristales que
amplifican la voluntad de quien los empuña. Donde cayó el fragmento mayor, el continente se hundió
y quedó rodeado por un abismo violeta. Esa meseta suspendida sobre el vacío es la **Frontera Rota**.

En su centro se alza el **Bastión de Ilun**, una fortaleza circular levantada alrededor de la
**Esquirla Mayor**, que todavía late con luz propia. Quien controla la Frontera controla las
esquirlas, y quien controla las esquirlas decide el futuro de Velkaris.

## Los tres reinos

### Hegemonía de Brasalta: fuego y forja (ámbar)
Imperio del desierto volcánico del norte. Lo gobiernan ingenieros-sacerdotes que templan obsidiana
en el **Ascua Primordial**, un volcán que nunca se apaga. Sociedad de castas de forja, disciplina
militar y murallas de vidrio negro. Para Brasalta, las esquirlas son chispas robadas al Ascua y les
pertenecen por derecho.
> *"Lo que no se funde, se templa."*

### Concilio de Umbravel: bruma y raíz (jade)
Manglares del suroeste cubiertos por una bruma perpetua y hongos bioluminiscentes. Los gobierna un
concilio de alquimistas que "escuchan" la **Raíz Abisal**, una red de micelio que conecta todo su
territorio. Maestros del veneno, la curación y el sigilo. Creen que las esquirlas son semillas y que
la Frontera debe germinar.
> *"Toda raíz encuentra su camino."*

### Clanes de Céfira: tormenta y canto (celeste)
Nómadas de las islas flotantes del sureste, archipiélagos que derivan por el cielo. Encierran
tormentas dentro de las esquirlas y las dirigen con el canto. Sociedad de clanes, honor y deudas de
sangre. Para ellos, las esquirlas son lágrimas de Ilun que hay que devolver al cielo.
> *"El viento no pide permiso."*

## La guerra por la Frontera: mecánicas de asedio

| Estructura | Descripción | Regla en el MVP |
|---|---|---|
| **Santuario** (uno por reino) | Campamento fortificado al borde de la Frontera | Zona segura: los propios son invulnerables y la *Guardia del Santuario* hace 60 de daño por segundo a los intrusos (evita el *spawn camping*). Se reaparece aquí a los 6 s. |
| **Atalayas** (Ocaso, Alba, Abismo) | Torres de vigía entre cada par de santuarios | Se capturan permaneciendo en su **Círculo de Resonancia** (9 m). Más jugadores capturan más rápido (hasta 4). Con dos reinos dentro, el punto queda *en disputa* y se congela. Primero se neutraliza al dueño y luego se captura. **+1 punto cada 5 s.** |
| **Bastión de Ilun** | Fortaleza central: muralla circular con 3 portones, uno frente a cada santuario | Para entrar hay que **derribar un portón** (4000 PV) y luego capturar la Esquirla Mayor (6 m). El reino dueño atraviesa sus propios portones. Al cambiar de dueño, **los portones se reconstruyen**. La muralla bloquea la línea de visión. **+3 puntos cada 5 s.** |
| **Derribos** | Abatir a un enemigo | **+2 puntos** para tu reino. |
| **Campaña** | | El primer reino en llegar a **300 puntos** gana y la guerra se reinicia. |

## Clases

Las tres clases están disponibles para los tres reinos. El reino da identidad y bando; la clase,
el papel en el asedio.

### Quebrantamuros: tanque de asedio (1400 PV)
Las legiones de Brasalta inventaron el **martillo resonante**, una cabeza de esquirla que vibra en la
frecuencia de la piedra. Los otros reinos lo copiaron en menos de una generación.

| Tecla | Habilidad | Efecto |
|---|---|---|
| 1 | **Golpe Sísmico** | 110 de daño cuerpo a cuerpo (3,5 m). **x4 contra portones** (440). Enfriamiento 1,2 s. |
| 2 | **Baluarte** | Reduce a la mitad el daño recibido durante 4 s. Enfriamiento 16 s. |
| 3 | **Embestida** | Carga 9 m en 0,3 s hacia donde mira. Enfriamiento 10 s. |

*En el asedio:* abre la brecha y aguanta en ella.

### Cantor de Esquirlas: soporte / daño a distancia (900 PV)
Los cantores de Céfira descubrieron que la luz lunar obedece a ciertas notas. Un buen coro de
cantores decide quién se queda con una atalaya.

| Tecla | Habilidad | Efecto |
|---|---|---|
| 1 | **Rayo de Esquirla** | 95 de daño a 28 m. Requiere línea de visión. x0,5 contra portones. Enfriamiento 1,5 s. |
| 2 | **Pulso Restaurador** | Cura 220 PV a ti y a los aliados en 9 m. Enfriamiento 8 s. |
| 3 | **Sello de Resonancia** | Durante 8 s cuentas **doble** al capturar atalayas y el Bastión. Enfriamiento 20 s. |

*En el asedio:* mantiene vivo al grupo y acelera las capturas.

### Zapador de Bruma: infiltrador / saboteador (1000 PV)
Los zapadores de Umbravel se envuelven en esporas de bruma para desaparecer y fabrican cargas con
hongos explosivos que crecen dentro de la madera de los portones.

| Tecla | Habilidad | Efecto |
|---|---|---|
| 1 | **Cuchilla Doble** | 90 de daño (3 m). **x2 por la espalda** (180). Enfriamiento 1 s. |
| 2 | **Velo de Bruma** | 7 s invisible para los enemigos a más de 4 m. El servidor ni siquiera les envía tu posición. Atacar o recibir daño lo rompe. Enfriamiento 18 s. |
| 3 | **Carga de Zapa** | Coloca un explosivo en un portón: 700 de daño a los 3 s. Enfriamiento 14 s. |

*En el asedio:* se cuela por los flancos, elimina cantores y vuela portones.

## Ideas para la siguiente fase de diseño
- **Corazones de Esquirla (reliquias):** cada santuario guarda una; robarla y llevarla a tu santuario
  da un bonus a todo el reino. El portador va más lento y es visible para todos.
- **Líneas de suministro:** solo se puede atacar el Bastión si tu reino controla una atalaya adyacente.
- **Armas de asedio:** ariete de obsidiana (Brasalta), catapulta de esporas (Umbravel), arpón de
  tormenta (Céfira), construidas con recursos que generan las atalayas.
- **Rangos de reino:** puntos de reino por participar en capturas, con habilidades pasivas desbloqueables.
