# AGENTS.md

Flutter app (POS de restaurante "Conwich"). Paquete Dart: `test_code_02` — los imports usan
`package:test_code_02/...`, NO el nombre de la app.

## Comandos
- `flutter pub get`
- `flutter analyze` — `analysis_options.yaml` excluye build/ y todas las carpetas de plataforma
- `flutter test` — corre unit + "integración" de BD (usa sqflite_common_ffi, no requiere dispositivo).
  `dart_test.yaml` fija `concurrency: 1` porque todos los archivos comparten la misma BD SQLite.
- `flutter run` (o `flutter run -d chrome` para web)
- `flutter build apk` / `flutter build web` — build de release

## Build / plataformas
- Android: `applicationId`/namespace `com.example.test_code_02`, Java/Kotlin 17,
  minSdk/targetSdk/compileSdk toman los defaults de Flutter. Gradle wrapper 9.3.1, AGP 9.1.0,
  Kotlin 2.4.0. El release firma con las debug keys (sin keystore propio). versionName/versionCode
  salen de `pubspec.yaml` (1.0.0+1). El canal "Beta 1" es solo una etiqueta visual en
  `lib/core/app_info.dart`; no forma parte de la versión para iOS.
- iOS: bundle id `com.example.testCode02`, display name `Conwich`. Web: `<title>` = `Conwich`.

## Arquitectura
- Sin gestor de estado: `setState` + singletons (`Sesion.instance`). Las páginas usan repositorios directamente.
- `lib/features/<feature>/presentation/*.dart` — pantallas (auth, sales, cash, menu, products, inventory, users, reports, dashboard, shell).
- `lib/core/*_repository.dart` — acceso a datos (auth, cash, catalog, menu, report, sales).
- `lib/ui/common.dart` — widgets y helpers compartidos (parseAmount, formatMoney, AppCard, StatCard, showAppMessage, appInput).
- `lib/main.dart` — tema Material 3 central + `StartupGate` (login vs AppShell según sesión).

## Base de datos (SQLite / sqflite)
- `lib/data/database/app_database.dart` — singleton `AppDatabase.instance`, schema versionado a mano.
- `version: 13` (`AppDatabase.schemaVersion`); DB file `sazon_restaurante_v2.db`. Las claves
  foráneas se desactivan durante la migración y se activan en `onOpen` (`PRAGMA foreign_keys = ON`).
- Para cambiar schema: subir `version`, añadir `onUpgrade`. Las vistas `v_stock_insumos` y
  `v_stock_productos` se dropean y recrean en cada upgrade (ya se hace en `_createSchema`).
- `unidades_medida.familia`/`factor_base` permiten convertir L↔ml y kg↔g en las recetas.
- La receta es opcional. Al vender, el consumo se limita al stock disponible (nunca deja
  negativos) y el faltante queda registrado en `faltantes_insumo` (se consulta en Reportes).
- `insumos.venta_directa` genera/actualiza un producto vinculado (`producto_id`) con receta de
  1 unidad; su categoría queda `siempre_disponible = 1`. Los productos `DIRECTO` viejos se
  migran automáticamente a insumo + receta al subir a v7 y el stock actual se conserva.
- `_afterOpen` siembra categorías planas: `PLATOS SUELTOS`, `SOPAS`, `BEBIDAS CALIENTES`,
  `REFRESCOS` y `FRAPPES`. No hay categorías padre ni subcategorías (`parent_id` queda en NULL).
  Las categorías se guardan siempre en mayúsculas y se pueden crear nuevas desde Productos.
  Los insumos de venta directa guardan su foto en el producto.
- `cajas` usa `numero_turno` consecutivo por día (`Turno 1, 2, 3…`), no `MAÑANA/TARDE`.
  Cerrar una caja ya no cierra el menú del día.
- Menú del día replica el catálogo de Ventas agrupado por categoría plana, con chips de
  categorías (por color) para filtrar. Tocar un plato lo agrega o quita del menú al instante; los
  platos del menú llevan borde verde con check y los agotados salen en rojo y bloqueados (se
  reactivan con el control de la tarjeta). Al abrir un día sin menú se copia automáticamente la
  configuración del menú anterior (platos y combos); si hay un menú programado para esa fecha se
  respeta. "Programar días" copia la configuración a los siguientes días. El menú solo se publica
  (`HABILITADO`); no se cierra. "Limpiar" vacía platos y combos. La venta directa va en una
  sección SIEMPRE DISPONIBLES. Si no hay caja abierta, Ventas muestra un botón "Ir a Caja".
- Los almuerzos/combos se arman en la sección "Almuerzos y combos": se seleccionan uno o más
  productos (sin cantidades), se define nombre y precio. Desde 2 productos se sugiere
  automáticamente `suma × 0.90`, pero el usuario puede editar solo el precio. El combo se guarda
  como producto compuesto (`productos.es_compuesto = 1`), sus componentes en
  `producto_componentes` y su publicación diaria en `menu_dia_combos`. Los productos componentes
  siguen vendiéndose por separado y ningún producto necesita receta.
- El estado del menú se llama `HABILITADO` (antes `PUBLICADO`) en BD, código y textos; la columna
  es `habilitado_en`. El tablero ofrece "Empezar el día" (lleva al menú y de ahí un atajo a Caja).
- `app_meta` (fila única): `instalacion_id` (UUID estable de la instalación), fecha del último
  respaldo y configuración de respaldo en Drive (`drive_habilitado`, `drive_carpeta_uri`,
  `drive_carpeta_nombre`, `drive_retencion`, `drive_al_cerrar_caja`, `drive_frecuencia`,
  `drive_ultimo_exito`, `drive_ultimo_error`). Se escribe **antes** de copiar el archivo, así la
  fecha viaja dentro del respaldo.
- `detalle_pedido.es_componente` marca las líneas hijas de un combo. No suman ventas; sirven para
  descontar stock de productos directos y conservar trazabilidad. La receta de cada componente se
  consume solo si existe.
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
  más vendidos, productos con precio unitario, salidas detalladas y pedidos) y en Excel (hojas
  Resumen, Productos, Salidas, Pedidos, Gráfico y Faltantes). El gráfico de Excel usa barras de
  celdas coloreadas porque el paquete `excel` no soporta gráficos nativos.
- Respaldo en Google Drive: se usa el selector de carpetas de Android (SAF), no Google Cloud ni
  OAuth. `android/.../MainActivity.kt` expone un `MethodChannel` con elegir carpeta, verificar
  permiso, escribir, listar y borrar. La carpeta elegida se guarda en `app_meta`. Las copias se
  suben al cerrar caja (según configuración) y en el inicio si la frecuencia está vencida; se
  conservan las últimas N copias (`drive_retencion`, por defecto 30).

## Convenciones / gotchas
- **Regla: el sistema nunca depende de que los productos tengan receta.** Un `PREPARADO` sin
  receta se vende igual (solo no descuenta insumos); `motivoNoDisponible` no lo bloquea y el
  carrito/pedido se registran sin error.
- Login por defecto sembrado: usuario `admin` / contraseña `1234` (hash SHA-256, `lib/core/password_utils.dart`).
- Dinero en Bolivianos (`Bs`, `formatMoney`); entrada decimal con coma (`parseAmount`). Fechas como texto SQL
  vía `sqlDate`/`sqlDateTime` (`lib/core/date_utils.dart`).
- UI y comentarios en español. Roles/perfiles y permisos en `lib/core/session.dart` (`Permiso`, `Perfil`).
- Test unitario verifica el hash SHA-256 exacto de `1234`; no cambiar el algoritmo sin actualizar `test/widget_test.dart`.
