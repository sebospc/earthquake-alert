# Borrador: oficina de la senadora María Lucía Villalba

Estado: BORRADOR. No enviar sin aprobación.

## Destinatario y canal (verificado 24-sep-2026)

- Correo: `maria.villalba@senado.gov.co`. Sale del directorio oficial de senadores en senado.gov.co. La página protege el correo con JavaScript; lo decodifiqué del HTML. No encontré un correo aparte de la UTL, así que este es el canal oficial que existe.
- Teléfono del Senado: (601) 382 3000, Edificio Nuevo del Congreso.
- Partido: Nuevo Liberalismo. Vicepresidenta de la Comisión Sexta desde julio de 2026.
- Proyecto: radicado el 18-ago-2026. Crea el SNAST, pone al Servicio Geológico Colombiano como autoridad de la alerta y usa difusión celular universal (cell broadcast), radio y TV. **No encontré el número del proyecto ni la comisión a la que fue repartido.** La Comisión Sexta es la probable (comunicaciones, espectro, calamidades), pero está por confirmar. La carta lo pregunta.

Cómo participar:

- Ley 5 de 1992, artículo 230: cualquier persona puede presentar observaciones sobre un proyecto que esté en una comisión. Se hacen por escrito, y se envía copia al ponente y a los miembros de la comisión. Para intervenir en persona hay que inscribirse antes en el libro que abre la secretaría de la comisión.
- Las audiencias públicas las convoca la mesa directiva de la comisión. La oficina de la autora es la que sabe si habrá una y cuándo.

Fuentes: [directorio de senadores](https://www.senado.gov.co/index.php/el-senado/senadores), [nota del Senado sobre el proyecto](https://www.senado.gov.co/index.php/el-senado/noticias/7522-de-la-tragedia-a-la-prevencion-proyecto-busca-que-colombia-se-anticipe-a-futuros-terremotos), [Infobae 18-ago](https://www.infobae.com/colombia/2026/08/18/en-colombia-crearian-un-sistema-nacional-de-alerta-sismica-temprana-tras-el-terremoto-de-74-unificaria-alertas-en-telefonia-radio-y-television/), [vicepresidencia Comisión Sexta](https://laultima.com.co/2026/07/29/maria-lucia-villalba-sera-vicepresidenta-de-la-comision-sexta-del-senado/), [Ley 5 de 1992](http://www.secretariasenado.gov.co/senado/basedoc/ley_0005_1992_pr006.html), [Congreso Visible sobre audiencias](https://congresovisible.uniandes.edu.co/articulo/audiencias-publicas-el-espacio-de-la-ciudadania-en-el-congreso/62/).

---

**Asunto:** Proyecto SNAST: mediciones reales de alertas sísmicas en celulares en Colombia

Senadora Villalba y equipo de la UTL:

Les escribo por el proyecto de ley del Sistema Nacional de Alerta Sísmica Temprana. Tengo un laboratorio privado en Medellín que mide cómo llegan hoy las alertas sísmicas de Android a Colombia, y creo que tres datos les pueden servir para la ponencia.

**Hoy la mitad del problema es el iPhone.** Android tiene alertas sísmicas de Google en Colombia. El iPhone no tiene ninguna, porque Apple solo las ofrece en Estados Unidos y Taiwán. Quien tiene iPhone no recibe nada, y eso es justo lo que el cell broadcast del proyecto resolvería.

**Medimos la latencia real.** El 23 de septiembre, en un sismo M4.5 cerca de Chaparral, Tolima, la alerta de Google llegó 17,6 segundos después del origen. Lo que vale esa demora depende de la distancia, porque la sacudida fuerte viaja a unos 3,5 km por segundo:

| distancia al epicentro | aviso antes de la sacudida |
|---|---|
| 20 km | ninguno, llega 12 s tarde |
| 50 km | ninguno, llega 3 s tarde |
| 100 km | 11 s |
| 200 km | 40 s |
| 300 km | 68 s |

O sea que el aviso sirve de verdad a más de unos 80 km. Google mismo reporta que solo el 36% de sus usuarios recibe la alerta antes de sentir el temblor. Unas horas después, en un segundo sismo, solo llegó el aviso posterior, 5 minutos tarde. Estos límites conviene que el proyecto los diga de frente, para que nadie espere lo que la física no permite.

**Una idea para el articulado.** En California el sistema oficial (ShakeAlert, del USGS) y Google firmaron un acuerdo: las alertas oficiales llegan a los Android por el sistema operativo, y Google cubre con su propia red lo que la red oficial no alcanza. Propongo que el proyecto deje abierta esa puerta: que el SGC pueda firmar convenios con plataformas como Google o Apple, tanto para usarlas como canal de entrega como para usar sus detecciones como fuente complementaria mientras la red nacional crece. El SGC seguiría siendo la única autoridad de la alerta.

Dos preguntas:

1. ¿Cuál es el número del proyecto y a qué comisión fue repartido?
2. Si se convoca una audiencia pública, me gustaría inscribirme para presentar estos datos. ¿Con quién debo coordinarlo?

Puedo enviar las capturas y el método completo. El laboratorio es privado y no ofrece ningún servicio al público.

Cordialmente,

Sebastián Cabarcas
Medellín
[teléfono]
[correo]

---

## Notas para revisar antes de enviar

- **Corregí una premisa del encargo.** En California no es que el sistema oficial use detecciones de Google como fuente. Es al revés: Google entrega las alertas de ShakeAlert en los Android. La propuesta de la carta cubre las dos direcciones sin afirmar algo que no pasó.
- La tabla usa la latencia de un solo evento. Es poco, y la carta no lo esconde, pero si en la audiencia preguntan por la muestra hay que decir que son dos capturas.
- No mencioné que el laboratorio usa emuladores con ubicación simulada. No hace falta para el argumento y abre una discusión de términos de Google que no le sirve a la senadora. Si prefieren decirlo, va en una línea después de "Medimos la latencia real".
- Las negritas al inicio de cada bloque son para lectura rápida en una oficina que recibe muchos correos. Se pueden quitar.
