# AGENTS.md

Flutter app (POS de restaurante "Conwich"). Paquete Dart: `test_code_02` — los imports usan
`package:test_code_02/...`, NO el nombre de la app.

## Comandos
- `flutter pub get`
- `flutter analyze` — `analysis_options.yaml` excluye build/ y las carpetas de plataforma e
  ignora `deprecated_member_use` (Flutter 3.50 deprecó `package:flutter/material.dart` a favor de
  `material_ui`; la migración queda pendiente).
- `flutter test` — corre unit + "integración" de BD (usa sqflite_common_ffi, no requiere dispositivo).
  `dart_test.yaml` fija `concurrency: 1` porque todos los archivos comparten la misma BD SQLite.
- `flutter run` (o `flutter run -d chrome` para web)
- `flutter build apk` / `flutter build web` — build de release

## Build / plataformas
- Android: `applicationId`/namespace `com.example.test_code_02`, Java/Kotlin 17,
  minSdk/targetSdk/compileSdk toman los defaults de Flutter. Gradle wrapper 9.5.0, AGP 9.1.1,
  Kotlin 2.4.0. El release firma con las debug keys (sin keystore propio). versionName/versionCode
  salen de `pubspec.yaml` (1.0.0+1). El canal "Beta 1" es solo una etiqueta visual en
  `lib/core/app_info.dart`; no forma parte de la versión para iOS.
- iOS: bundle id `com.example.testCode02`, display name `Conwich`. Web: `<title>` = `Conwich`.

## Arquitectura
- Sin gestor de estado: `setState` + singletons (`Sesion.instance`). Las páginas usan repositorios directamente.
- `lib/features/<feature>/presentation/*.dart` — pantallas (auth, sales, cash, menu, products, inventory, users, reports, dashboard, shell).
- `lib/core/*_repository.dart` — acceso a datos (auth, cash, catalog, menu, report, sales).
- `lib/ui/common.dart` — widgets y helpers compartidos (parseAmount, formatMoney, AppCard, StatCard, showAppMessage, appInput).
- `validateDecimalAmount` y `decimalAmountInputFormatter` validan importes/cantidades numéricas.
  Usarlos en Productos, Caja y cobros; no aplicarlos ni cambiar el formulario de Insumos.
- `lib/main.dart` — tema Material 3 central + `StartupGate` (login vs AppShell según sesión).
- `AppShell` construye cada sección solo al visitarla y refresca solo la sección activa
  (cada pantalla tiene su propio token). El drawer (teléfono) y una barra lateral propia
  desplazable de arriba hacia abajo (tablet/escritorio, con `Key('rail-sidebar')`) muestran
  **solo los destinos** del menú. Un botón ☰ en el `AppBar` oculta/muestra la barra lateral en
  tablet/escritorio (solo visible mientras la ventana mida ≥ 860). Las acciones de sesión
  (cambiar/ver usuario, cambiar contraseña, respaldo y cerrar sesión) son iconos en la esquina
  superior derecha del `AppBar`.
  La barra reemplaza al `NavigationRail`, que desbordaba en tablets. El logo "Conwich" del
  `AppBar` y de la barra lleva al Tablero.

## Base de datos (SQLite / sqflite)
- `lib/data/database/app_database.dart` — singleton `AppDatabase.instance`, schema versionado a mano.
- `version: 19` (`AppDatabase.schemaVersion`); DB file `sazon_restaurante_v2.db`. Las claves
  foráneas se desactivan durante la migración y se activan en `onOpen` (`PRAGMA foreign_keys = ON`).
- Para cambiar schema: subir `version`, añadir `onUpgrade`. Las vistas `v_stock_insumos` y
  `v_stock_productos` se dropean y recrean en cada upgrade (ya se hace en `_createSchema`).
- La v14 agregó índices (`pagos(pedido_id)`, `consumos_insumo(insumo_id)`,
  `detalle_compra(insumo_id/producto_id)`, `detalle_pedido(producto_id)`,
  `detalle_conteo(insumo_id)`, `faltantes_insumo(fecha/pedido_id)`); no modifica datos y
  acelera las vistas de stock y los reportes.
- La v15 agrega a `detalle_pedido` modalidad de venta y snapshots de la sopa incluida en un
  completo; los productos compuestos anteriores quedan inactivos y conservados para historial.
- La v16 restaura la categoría base `PLATOS SUELTOS` sin fusionar ni borrar categorías.
- La v17 agrega `menus_dia.precio_almuerzo` (precio fijo del completo por día), la tabla
  `producto_presentaciones` (variantes/tamaños de refrescos), `compras.codigo` (código de
  compra) e `insumos.consumible` (bandera de no consumible). Solo agrega columnas/tablas; no
  modifica datos.
- La v18 agrega `app_meta.impresora_mac` e `impresora_nombre` (impresora térmica Bluetooth).
- La v19 agrega `cajas.sobrante` y `cajas.total_esperado` (arqueo con sobrante),
  `productos.agotado` (switch de Ventas/Menú), `productos.es_combo` (combos sin stock) y la
  tabla `devoluciones` (anulaciones con monto, método, usuario y motivo). También siembra la
  categoría `COMBOS` (`siempre_disponible = 1`). El índice `idx_detalle_componente` se crea en
  `_afterOpen` porque depende de `detalle_pedido.es_componente`, columna que llega en una
  migración.
- `unidades_medida.familia`/`factor_base` permiten convertir L↔ml y kg↔g en las recetas.
- La receta es opcional. Al vender, el consumo se limita al stock disponible (nunca deja
  negativos) y el faltante queda registrado en `faltantes_insumo` (se consulta en Reportes).
- `insumos.venta_directa` genera/actualiza un producto vinculado (`producto_id`) con receta de
  1 unidad; su categoría queda `siempre_disponible = 1`. Los productos `DIRECTO` viejos se
  migran automáticamente a insumo + receta al subir a v7 y el stock actual se conserva.
- Los insumos se cargan con **compras** (botón "Agregar cantidad" por insumo, que escribe en
  `compras` + `detalle_compra` y suma stock vía `v_stock_insumos`); el costo se recalcula por
  promedio ponderado si cambia. "Registrar pérdida" descuenta stock con un ajuste negativo en
  `ajustes_stock` (motivo `Pérdida`) sin tocar precios. El historial de compras se ve en la
  pestaña **Compras** de Reportes (y en el PDF/Excel). `insumos.consumible = 0` marca los no
  consumibles (cucharas, platos, vasos), que se listan aparte. El formulario de insumo registra
  nombre, unidad de medida, stock mínimo y costo; **no** carga stock inicial (entra por compras).
- Refrescos con presentaciones: la tabla `producto_presentaciones` guarda tamaños (nombre,
  precio, foto) de un producto base. En Productos se gestionan con el botón "Presentaciones"
  (solo categoría `REFRESCOS`); en Ventas, al tocar el refresco se elige la presentación. El
  stock sigue siendo del producto base; la presentación aporta nombre y precio (se conservan
  en el pedido vía `CartLine.presentacionId`).
- `_afterOpen` siembra categorías planas: `PLATOS SUELTOS`, `SOPAS`, `BEBIDAS CALIENTES`,
  `REFRESCOS`, `FRAPPES` y `COMBOS` (esta última siempre disponible). No hay categorías padre ni
  subcategorías (`parent_id` queda en NULL).
  Las categorías se guardan siempre en mayúsculas y se gestionan desde el **desplegable "Categoría"
  del filtro de la vista de Productos** (no dentro de los formularios): al tocarlo abre una lista con
  la fila "Todas", **+ Nueva categoría**, y por fila ✏️ editar y 🗑️ eliminar. El diálogo de
  categoría deja elegir el color con una paleta más deslizadores de matiz/saturación/brillo
  (`lib/ui/categoria_editor.dart`, compartido con el botón "Nueva" de los formularios y de Insumos;
  los desplegables de los formularios solo seleccionan). Las categorías del sistema por nombre (`PLATOS SUELTOS`, `SOPAS`,
  `BEBIDAS CALIENTES`, `REFRESCOS`, `FRAPPES`, `COMBOS`, `VENTA DIRECTA`) solo admiten cambiar el
  color: renombrarlas o borrarlas rompe sopa/completo/presentaciones y la siembra las recrearía.
  Al eliminar una categoría con productos se ofrece moverlos a otra categoría primero
  (`countProductosCategoria`, `moverProductosCategoria`, `deleteCategoria` en `CatalogRepository`).
  Los insumos de venta directa guardan su foto en el producto.
- `cajas` usa `numero_turno` consecutivo por día (`Turno 1, 2, 3…`), no `MAÑANA/TARDE`.
  Cerrar una caja ya no cierra el menú del día.
- Menú del día muestra todas las categorías de productos; las sopas se eligen con tarjetas que
  muestran su imagen (máximo una), y los productos de las demás categorías se agregan o quitan con
  un toque. El cambio se guarda **al instante** en la BD; el checkbox "Todos" de la categoría
  sigue funcionando. Solo `PLATOS SUELTOS` puede ser completo. En Ventas se calcula
  `precio_plato + precio_sopa`, salvo que el menú defina `precio_almuerzo` (precio fijo del
  completo por día, editable junto al selector de sopa).
  No hay modo "Editar/Listo", botón "Publicar menú", estado borrador ni "Crear menú con lo de ayer".
  Todo menú se habilita automáticamente y los productos habilitados aparecen en Ventas. Al abrir un
  día sin menú se copia automáticamente la configuración del menú anterior. "Programar días"
  copia la configuración a los siguientes días. El menú no se cierra. Los productos desactivados
  desde Productos se guardan en un desplegable
  "Productos deshabilitados" y se pueden reactivar; al reactivarlos quedan habilitados en el
  menú del día. La venta directa y los combos van en la sección SIEMPRE DISPONIBLES.
  En tablet (ventana ≥ 860) el panel "MENÚ DE HOY" queda fijo a la derecha; en teléfono se
  acomoda abajo. Si no hay caja abierta, Ventas muestra un botón "Ir a Caja".
  En Ventas, los productos activos que no están en el menú del día o están agotados se agrupan
  en una sección colapsable ("Productos agotados o fuera del menú"), oculta por defecto y no
  vendible.
- Todas las ventas son **directas** (se cobran al momento): no hay pedidos pendientes ni
  reservas. Se eliminó el botón "Guardar pendiente de pago", el modo "Agregar al pedido" y la
  sección "Pedidos pendientes de pago".
- Ventas (tablet/escritorio): el panel **Pedido** queda fijo a la **derecha** (~25%) y el catálogo ocupa
  el resto (~65%) con **3 productos por columna**; en teléfono el pedido se apila abajo. Los chips de
  categorías van en una **franja horizontal deslizable sin barra de scroll** (campo de búsqueda
  arriba): **"Todas"**
  primero y luego el **orden canónico** de `categorias_producto.orden` (PLATOS SUELTOS, SOPAS,
  BEBIDAS CALIENTES, REFRESCOS, FRAPPES, COMBOS, VENTA DIRECTA y las del usuario), con el color de
  la categoría y desplazamiento automático al chip elegido. Debajo
  del catálogo (columna izquierda) está el **historial de ventas del día** con pedido, hora,
  usuario, total, botón **ANULAR** y un botón de **ojo** que abre el detalle en un emergente
  (líneas, pagos y devolución). La sección de **productos agotados/fuera del menú** queda debajo
  del panel Pedido, en la columna derecha (en teléfono va al final). ANULAR no borra: marca el
  pedido y sus pagos como `ANULADO`, registra la devolución en `devoluciones` y mantiene la venta
  en el historial; pide un motivo obligatorio en un diálogo con estado propio. Puede anular
  cualquiera con `Permiso.ventas`. El switch **Agotado** de cada tarjeta oculta el producto de
  Ventas y se refleja en `productos.agotado` + `menu_dia_items`; desde el Menú se rehabilita.
- Caja: se muestra un único **"Total esperado del turno"** (`efectivo + QR − salidas`) y el
  cierre pide un **"Sobrante del turno"** con signo (negativo = faltante). `cerrarCaja` guarda
  `cajas.sobrante` y `cajas.total_esperado`; el efectivo contado y el QR verificado quedaron
  fuera de la UI. Al cerrar se ofrece imprimir el **movimiento del turno** (ventas efectivo,
  ventas QR, salida efectivo, sobrante y total esperado) por la misma vía que las notas. El
  historial de cajas muestra solo el día seleccionado, con cajero + rol, ventas efectivo/QR,
  salidas, total esperado y estado.
- El estado activo del menú se llama `HABILITADO` (antes `PUBLICADO`) en BD, código y textos; no
  hay estado borrador en el flujo. La columna es `habilitado_en`. El tablero ofrece "Empezar el día"
  (lleva al menú y de ahí un atajo a Caja).
- `app_meta` (fila única): `instalacion_id` (UUID estable de la instalación), fecha del último
  respaldo y configuración de respaldo en Drive (`drive_habilitado`, `drive_carpeta_uri`,
  `drive_carpeta_nombre`, `drive_retencion`, `drive_al_cerrar_caja`, `drive_frecuencia`,
  `drive_ultimo_exito`, `drive_ultimo_error`). Se escribe **antes** de copiar el archivo, así la
  fecha viaja dentro del respaldo.
- `detalle_pedido.modalidad_venta` distingue suelto/completo en `PLATOS SUELTOS` y guarda el snapshot de la sopa y su
  precio; una línea hija `es_componente` permite descontar también la sopa sin duplicar el ingreso.
  Los reportes agrupan por **producto + modalidad** (`Producto (suelto)`, `Producto (completo)`),
  muestran el precio real cobrado y cuentan la sopa incluida con **Bs 0** para que la suma de
  filas coincida con el total vendido. La receta de cada componente se consume solo si existe.
- Los combos nuevos se crean desde Productos con **"Nuevo combo"**: nombre, precio, selección
  múltiple de productos, imagen propia o la del primer componente, y categoría `COMBOS` por
  defecto (editable). Se guardan como producto normal (`es_compuesto = 0`) sin receta, por lo
  que **no descuentan stock ni insumos**; los componentes quedan en `producto_componentes` solo
  para mostrarlos. Los combos compuestos antiguos se conservan para el historial/backups.
- Import condicional de factory: `database_factory_web.dart if (dart.library.io) database_factory_io.dart`
  (sqflite vs sqflite_common_ffi_web). No romper este patrón.

## Respaldo
- `lib/core/backup/backup_service.dart` exporta condicionalmente `backup_service_io.dart` o
  `backup_service_web.dart` (en web solo funciona la exportación a Excel).
- Flujo: `AppDatabase.instance.close()` → copiar el `.db` → validar cabecera `SQLite format 3\0`.
  Restaurar reemplaza todo, guarda antes una copia en `<documentos>/respaldos_seguridad/` (máx. 5)
  y revierte si `PRAGMA integrity_check` falla.
- Las copias nuevas se llaman `conwich_respaldo_<fecha>.db` y
  `conwich_seguridad_<fecha>.db`; el formato de fecha no cambia. La compatibilidad al restaurar
  depende de `schemaVersion`, no del nombre del archivo. El `.db` de trabajo sigue siendo
  `sazon_restaurante_v2.db`.
- `excel_exporter.dart` genera una hoja por tabla; excluye `password_hash` y el BLOB `imagen`.
- `report_exporter.dart` genera el reporte del período en PDF tamaño carta (resumen, gráfico de
  ingresos, gráfico por cantidad, productos con precio unitario, cajas, anulados, salidas
  detalladas, pedidos y faltantes) y en Excel (hojas Resumen, Productos, Almuerzos, Sopas,
  Cajas, Anulados, Salidas, Pedidos, Gráfico, Gráfico cantidades y Faltantes).
  Los gráficos de Excel usan barras de celdas coloreadas porque el paquete `excel` no soporta
  gráficos nativos.
- En Reportes, administradores ven los reportes completos. Usuarios no administradores con acceso
  a Ventas solo ven sus propios pedidos en lectura, filtrados por `pedidos.usuario_id` y el rango
  elegido; no se agregan columnas ni tablas para esto.
- La pestaña **Cajas** agrupa por día/semana/mes/año y muestra efectivo, QR, salidas, total
  esperado y sobrante, con el cajero y su rol. La pestaña **Anulados** lista las devoluciones
  (pedido, fecha, usuario, método, monto y motivo). El tablero muestra ingresos, efectivo, QR,
  salidas, devoluciones y accesos rápidos a Reportes/Caja/Menú; los gastos de insumos no se
  descuentan del neto por ahora.
- Respaldo en Google Drive: se usa el selector de carpetas de Android (SAF), no Google Cloud ni
  OAuth. `android/.../MainActivity.kt` expone un `MethodChannel` con elegir carpeta, verificar
  permiso, escribir, listar y borrar. La carpeta elegida se guarda en `app_meta`. Las copias se
  suben al cerrar caja (según configuración) y en el inicio si la frecuencia está vencida; se
  conservan las últimas N copias (`drive_retencion`, por defecto 30).

## Impresión
- `lib/core/receipt_service.dart` genera la **nota de venta en PDF de 80 mm** con fuente
  **Roboto embebida** (`assets/fonts/Roboto-Regular.ttf` y `-Bold.ttf`) para que acentos y ñ se
  impriman bien; el alto de página se ajusta al contenido. La UI ya no lo usa para imprimir:
  queda para exportaciones/pruebas y como generador de PDF del mismo formato.
- Impresora térmica **Bluetooth de 80 mm** por ESC/POS: `lib/core/printer/printer_service.dart`
  arma los bytes (48 columnas) y usa el `MethodChannel`
  `com.example.test_code_02/bluetooth_printer` implementado en `MainActivity.kt`. La Golden Sky
  **GS-FJ80M-UB usa BLE GATT** (servicio `49535343-fe7d-4ae5-8fa9-9fafd205e455`, escritura
  `49535343-8841-43f4-a8d4-ecbe34729bb3`); el canal conecta por BLE (chunk 20 B con
  `onCharacteristicWrite`) y deja SPP como respaldo. No se habilitan notificaciones: el
  descriptor dejaba el GATT ocupado y la primera escritura fallaba. "Probar impresora" envía
  **un solo buffer** `1B 40 43 4F 4E 57 49 43 48 0A 0A 1B 64 03 1D 56 01` (CONWICH + avance +
  corte parcial) para que imprima antes de cortar. La comprobación real es el papel, no el
  callback. La configuración (`impresora_mac`/`impresora_nombre`) vive en `app_meta` y se edita
  en la pantalla **"Impresora"** (admin), que permite escanear BLE, probar y guardar.
- La venta se imprime en **dos fichas** dentro de un solo buffer ESC/POS:
  `imprimir → cortar → imprimir → cortar`.
  - **Cliente:** logo, `PEDIDO #` a 3x y una línea `Fecha: … Hora: …`. Sin precios.
  - **Vendedor:** logo, `PEDIDO #` a 2x, la misma línea de fecha/hora, detalle con
    cantidad y subtotal por línea, y cajero. Sin total, sin turno y sin "Gracias".
  El logo (`assets/images/logo_ticket.png`, recortado a 1 bit) usa el **mismo ancho**
  en ambas fichas (120 px en ESC/POS, 18 mm en PDF) y se envía como raster `GS v 0`.
  Si no carga, la venta se imprime igual sin logo. El PDF de 80 mm replica las dos
  fichas en dos páginas.
- Velocidad BLE: al descubrir servicios se pide **MTU 247** y se usa un chunk de
  `(mtu − 3)` hasta **96 bytes** con una pausa de ~8 ms entre escrituras (y respaldo a
  20 si la térmica rechaza el chunk). No se cambia la prioridad de conexión porque en
  esta impresora provocaba desconexiones `status=22`. La conexión se mantiene abierta
  después de imprimir para reutilizarla en la siguiente venta. El logo raster se cachea
  de forma estática y se envía una sola vez por tamaño. Si la impresora se desconecta
  a mitad de la impresión, la app pregunta **Reintentar / Cancelar**; el PDF ya no se
  abre automáticamente.
- Al cobrar se mantiene el diálogo "¿Imprimir las fichas del pedido?" y al cerrar caja
  se ofrece imprimir el **movimiento del turno**: ambos usan **solo la impresora directa**
  configurada en `app_meta`. Si no hay impresora guardada o la conexión falla, se muestra
  un error para configurarla/reintentar; no se abre PDF. Reportes → Pedidos usa la misma
  impresión directa para reimprimir la nota.

## Convenciones / gotchas
- **Regla: el sistema nunca depende de que los productos tengan receta.** Un `PREPARADO` sin
  receta se vende igual (solo no descuenta insumos); `motivoNoDisponible` no lo bloquea y el
  carrito/pedido se registran sin error.
- Login por defecto sembrado: usuario `admin` / contraseña `1234` (hash SHA-256, `lib/core/password_utils.dart`).
- Dinero en Bolivianos (`Bs`, `formatMoney`); entrada decimal con coma (`parseAmount`). Fechas como texto SQL
  vía `sqlDate`/`sqlDateTime` (`lib/core/date_utils.dart`).
- UI y comentarios en español. Roles/perfiles y permisos en `lib/core/session.dart` (`Permiso`, `Perfil`).
- Test unitario verifica el hash SHA-256 exacto de `1234`; no cambiar el algoritmo sin actualizar `test/widget_test.dart`.
