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
- `version: 11` (`AppDatabase.schemaVersion`); DB file `sazon_restaurante_v2.db`. Las claves
  foráneas se desactivan durante la migración y se activan en `onOpen` (`PRAGMA foreign_keys = ON`).
- Para cambiar schema: subir `version`, añadir `onUpgrade`. Las vistas `v_stock_insumos` y
  `v_stock_productos` se dropean y recrean en cada upgrade (ya se hace en `_createSchema`).
- `unidades_medida.familia`/`factor_base` permiten convertir L↔ml y kg↔g en las recetas.
- La receta es opcional. Al vender, el consumo se limita al stock disponible (nunca deja
  negativos) y el faltante queda registrado en `faltantes_insumo` (se consulta en Reportes).
- `insumos.venta_directa` genera/actualiza un producto vinculado (`producto_id`) con receta de
  1 unidad; su categoría queda `siempre_disponible = 1`. Los productos `DIRECTO` viejos se
  migran automáticamente a insumo + receta al subir a v7 y el stock actual se conserva.
- `_afterOpen` siembra la categoría base `ALMUERZO` y sus subcategorías `PLATO SUELTO` y
  `COMPLETO` (el formulario de producto usa una de ellas por defecto). Las categorías se guardan
  siempre en mayúsculas. `Desayuno` ya no existe. Los insumos de venta directa guardan su foto
  en el producto.
- `cajas` usa `numero_turno` consecutivo por día (`Turno 1, 2, 3…`), no `MAÑANA/TARDE`.
  Cerrar una caja ya no cierra el menú del día.
- Menú del día replica el catálogo de Ventas agrupado por categoría/subcategoría, con chips de
  categorías (por color) para filtrar. Tocar un plato lo agrega o quita del menú al instante; los
  platos del menú llevan borde verde con check y los agotados salen en rojo y bloqueados (se
  reactivan con el control de la tarjeta). "Crear menú" arranca con los platos del día anterior y
  "Limpiar" vacía el menú. La venta directa va en una sección SIEMPRE DISPONIBLES. Si no hay caja
  abierta, Ventas muestra un botón "Ir a Caja".
- El estado del menú se llama `HABILITADO` (antes `PUBLICADO`) en BD, código y textos; la columna
  es `habilitado_en`. El tablero ofrece "Empezar el día" (lleva al menú y de ahí un atajo a Caja).
- `app_meta` (fila única): `instalacion_id` (UUID estable de la instalación) y fecha del último
  respaldo. Se escribe **antes** de copiar el archivo, así la fecha viaja dentro del respaldo.
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

## Convenciones / gotchas
- Login por defecto sembrado: usuario `admin` / contraseña `1234` (hash SHA-256, `lib/core/password_utils.dart`).
- Dinero en Bolivianos (`Bs`, `formatMoney`); entrada decimal con coma (`parseAmount`). Fechas como texto SQL
  vía `sqlDate`/`sqlDateTime` (`lib/core/date_utils.dart`).
- UI y comentarios en español. Roles/perfiles y permisos en `lib/core/session.dart` (`Permiso`, `Perfil`).
- Test unitario verifica el hash SHA-256 exacto de `1234`; no cambiar el algoritmo sin actualizar `test/widget_test.dart`.
