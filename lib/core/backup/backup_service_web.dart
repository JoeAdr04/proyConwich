import 'dart:typed_data';
import 'dart:ui' show Rect;

import '../../data/database/app_database.dart';
import 'backup_models.dart';

/// En web la base vive en IndexedDB y no existe un archivo que copiar, así que
/// el respaldo completo queda deshabilitado. La exportación a Excel sí
/// funciona en esta plataforma (`ExcelExporter`).
class BackupService {
  BackupService({
    Future<String> Function()? rutaTemporal,
    Future<String> Function()? rutaDocumentos,
  });

  bool get disponible => false;

  /// En web no se restaura, así que nunca se conservan administradores.
  int adminsConservados = 0;

  Future<Map<String, Object?>?> metaActual() =>
      AppDatabase.instance.leerAppMeta();

  Never _noSoportado() => throw UnsupportedError(
    'El respaldo completo solo está disponible en la aplicación instalada '
    '(Android). En el navegador puedes exportar a Excel.',
  );

  Future<CopiaCreada> crearCopia({required String motivo}) async =>
      _noSoportado();

  Future<void> compartirCopia(CopiaCreada copia, {Rect? origen}) async =>
      _noSoportado();

  Future<bool> guardarCopia(CopiaCreada copia) async => _noSoportado();

  Future<({String nombre, Uint8List bytes})?> elegirCopia() async =>
      _noSoportado();

  Future<Uint8List> leerArchivo(String ruta) async => _noSoportado();

  Future<InspeccionCopia> inspeccionar(
    Uint8List bytes, {
    required String nombre,
    DateTime? fechaArchivo,
  }) async => _noSoportado();

  Future<CopiaSeguridad> restaurar(InspeccionCopia copia) async =>
      _noSoportado();

  Future<CopiaSeguridad> crearCopiaSeguridad() async => _noSoportado();

  Future<List<CopiaSeguridad>> listarCopiasSeguridad() async => const [];

  Future<void> purgarCopiasSeguridad({int maximo = 5}) async {}

  Future<CopiaSeguridad> restaurarDesdeArchivo(String ruta) async =>
      _noSoportado();
}
