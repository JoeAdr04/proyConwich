import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/database/app_database.dart';
import '../app_info.dart';
import '../date_utils.dart';
import 'backup_models.dart';

/// Implementación nativa del respaldo: copia el archivo SQLite completo.
class BackupService {
  BackupService({
    Future<String> Function()? rutaTemporal,
    Future<String> Function()? rutaDocumentos,
  }) {
    _rutaTemporal = rutaTemporal;
    _rutaDocumentos = rutaDocumentos;
  }

  late final Future<String> Function()? _rutaTemporal;
  late final Future<String> Function()? _rutaDocumentos;

  Future<Directory> _temporal() async {
    if (_rutaTemporal != null) return Directory(await _rutaTemporal());
    return getTemporaryDirectory();
  }

  Future<Directory> _documentos() async {
    if (_rutaDocumentos != null) return Directory(await _rutaDocumentos());
    return getApplicationDocumentsDirectory();
  }

  static const _mimeDb = 'application/x-sqlite3';
  static const _cabecera = 'SQLite format 3\u0000';

  bool get disponible => true;

  Future<Map<String, Object?>?> metaActual() =>
      AppDatabase.instance.leerAppMeta();

  /// Crea una copia consistente: registra la fecha dentro de la base, cierra
  /// la conexión y copia el archivo. La app se reconecta sola al volver a
  /// consultar.
  Future<CopiaCreada> crearCopia({required String motivo}) async {
    // Asegura que la base exista y que `app_meta` esté creada.
    await AppDatabase.instance.database;
    await AppDatabase.instance.marcarRespaldo(
      motivo: motivo,
      appVersion: appVersion,
    );
    final origen = File(await AppDatabase.instance.rutaArchivo);
    await AppDatabase.instance.close();
    if (!await origen.exists()) {
      throw StateError('No se encontró el archivo de la base de datos.');
    }
    await _limpiarJournal(origen.path);

    final dir = Directory(p.join((await _temporal()).path, 'respaldos'));
    await dir.create(recursive: true);
    final nombre = 'conwich_respaldo_${_stamp(DateTime.now())}.db';
    final destino = File(p.join(dir.path, nombre));
    await origen.copy(destino.path);

    final bytes = await destino.readAsBytes();
    _validarCabecera(bytes);
    return CopiaCreada(
      nombre: nombre,
      ruta: destino.path,
      bytes: bytes,
      fecha: DateTime.now(),
    );
  }

  Future<void> compartirCopia(CopiaCreada copia, {Rect? origen}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(copia.ruta, mimeType: _mimeDb)],
        title: 'Respaldo de Conwich',
        subject: 'Respaldo Conwich ${_stamp(copia.fecha)}',
        sharePositionOrigin: origen,
      ),
    );
  }

  /// Guarda el respaldo donde el usuario elija (Descargas, Drive, etc.).
  Future<bool> guardarCopia(CopiaCreada copia) async {
    final uri = await FilePicker.saveFile(
      fileName: copia.nombre,
      bytes: copia.bytes,
      mimeType: _mimeDb,
      dialogTitle: 'Guardar respaldo',
    );
    return uri != null;
  }

  /// Permite elegir un archivo `.db` y devuelve su contenido.
  Future<({String nombre, Uint8List bytes})?> elegirCopia() async {
    final archivo = await FilePicker.pickFile(dialogTitle: 'Elegir respaldo');
    if (archivo == null) return null;
    final bytes = await archivo.readAsBytes();
    return (nombre: archivo.name, bytes: bytes);
  }

  Future<Uint8List> leerArchivo(String ruta) => File(ruta).readAsBytes();

  Future<InspeccionCopia> inspeccionar(
    Uint8List bytes, {
    required String nombre,
    DateTime? fechaArchivo,
  }) async {
    _validarCabecera(bytes);
    final dir = await _temporal();
    final temp = File(
      p.join(
        dir.path,
        'inspeccion_${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    await temp.writeAsBytes(bytes, flush: true);
    Database? db;
    try {
      // Se abre una copia temporal, no el archivo elegido por el usuario.
      db = await openDatabase(temp.path, singleInstance: false);
      final versionRow = await db.rawQuery('PRAGMA user_version');
      final schemaVersion =
          (versionRow.first['user_version'] as num?)?.toInt() ?? 0;

      final integridad = await db.rawQuery('PRAGMA integrity_check');
      final detalle = integridad.isEmpty
          ? 'sin respuesta'
          : '${integridad.first.values.first}';
      final integridadOk = detalle.toLowerCase() == 'ok';

      Map<String, Object?>? meta;
      try {
        final rows = await db.query('app_meta', limit: 1);
        if (rows.isNotEmpty) meta = rows.first;
      } catch (_) {
        // Copias anteriores a la v6 no tienen metadatos.
      }

      final conteos = <String, int>{};
      for (final tabla in const [
        'usuarios',
        'productos',
        'insumos',
        'pedidos',
        'gastos',
      ]) {
        try {
          conteos[tabla] =
              Sqflite.firstIntValue(
                await db.rawQuery('SELECT COUNT(*) FROM $tabla'),
              ) ??
              0;
        } catch (_) {
          conteos[tabla] = 0;
        }
      }

      return InspeccionCopia(
        nombreArchivo: nombre,
        bytes: bytes,
        sha256: _sha256(bytes),
        schemaVersion: schemaVersion,
        integridadOk: integridadOk,
        integridadDetalle: detalle,
        tieneMetadata: meta != null,
        fechaRespaldo: parseSqlDateTime(meta?['ultimo_respaldo_en'] as String?),
        fechaArchivo: fechaArchivo,
        appVersion: meta?['ultimo_respaldo_app'] as String?,
        motivo: meta?['ultimo_respaldo_motivo'] as String?,
        instalacionId: meta?['instalacion_id'] as String?,
        conteos: conteos,
      );
    } finally {
      await db?.close();
      await _limpiarJournal(temp.path);
      if (await temp.exists()) await temp.delete();
    }
  }

  /// Reemplaza la base actual por la copia indicada. Antes guarda una copia
  /// de seguridad y, si algo falla, la restaura.
  Future<CopiaSeguridad> restaurar(InspeccionCopia copia) async {
    if (!copia.integridadOk) {
      throw StateError('La copia está dañada o incompleta.');
    }
    if (!copia.versionCompatible(AppDatabase.schemaVersion)) {
      throw StateError(
        'La copia es de una versión más nueva (v${copia.schemaVersion}) que '
        'esta aplicación (v${AppDatabase.schemaVersion}). Actualiza la app.',
      );
    }

    final seguridad = await crearCopiaSeguridad();
    final destino = File(await AppDatabase.instance.rutaArchivo);
    await AppDatabase.instance.close();
    try {
      await _limpiarJournal(destino.path);
      await destino.writeAsBytes(copia.bytes, flush: true);
      final db = await AppDatabase.instance.database;
      final check = await db.rawQuery('PRAGMA integrity_check');
      final ok =
          check.isNotEmpty &&
          '${check.first.values.first}'.toLowerCase() == 'ok';
      if (!ok) {
        throw StateError('La copia restaurada no pasó la verificación.');
      }
      return seguridad;
    } catch (error) {
      // Revertir al estado anterior.
      await AppDatabase.instance.close();
      await destino.writeAsBytes(
        await File(seguridad.ruta).readAsBytes(),
        flush: true,
      );
      await AppDatabase.instance.database;
      throw StateError(
        'No se pudo restaurar la copia: $error. Se recuperó el estado anterior.',
      );
    }
  }

  /// Copia automática que se guarda en la carpeta privada de la app.
  Future<CopiaSeguridad> crearCopiaSeguridad() async {
    final copia = await crearCopia(motivo: 'seguridad_pre_restauracion');
    final dir = await _dirSeguridad();
    final nombre = 'conwich_seguridad_${_stamp(DateTime.now())}.db';
    final destino = File(p.join(dir.path, nombre));
    await destino.writeAsBytes(copia.bytes, flush: true);
    // La copia temporal ya cumplió su función.
    try {
      final temporal = File(copia.ruta);
      if (await temporal.exists()) await temporal.delete();
    } catch (_) {
      // Ignorar: el sistema limpia la caché.
    }
    await purgarCopiasSeguridad(maximo: 5);
    return CopiaSeguridad(
      nombre: nombre,
      ruta: destino.path,
      fecha: copia.fecha,
      tamanoBytes: copia.tamanoBytes,
      motivo: 'Antes de restaurar',
    );
  }

  Future<List<CopiaSeguridad>> listarCopiasSeguridad() async {
    final dir = await _dirSeguridad();
    final archivos = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.db'))
        .cast<File>()
        .toList();
    final copias = <CopiaSeguridad>[];
    for (final archivo in archivos) {
      final stat = await archivo.stat();
      copias.add(
        CopiaSeguridad(
          nombre: p.basename(archivo.path),
          ruta: archivo.path,
          fecha: stat.modified,
          tamanoBytes: stat.size,
          motivo: 'Antes de restaurar',
        ),
      );
    }
    copias.sort((a, b) => b.fecha.compareTo(a.fecha));
    return copias;
  }

  Future<void> purgarCopiasSeguridad({int maximo = 5}) async {
    final copias = await listarCopiasSeguridad();
    for (final copia in copias.skip(maximo)) {
      try {
        await File(copia.ruta).delete();
      } catch (_) {
        // Si no se puede borrar, se deja para la próxima.
      }
    }
  }

  /// Restaura directamente una copia de seguridad guardada en la app.
  Future<CopiaSeguridad> restaurarDesdeArchivo(String ruta) async {
    final archivo = File(ruta);
    if (!await archivo.exists()) {
      throw StateError('El archivo ya no existe.');
    }
    final bytes = await archivo.readAsBytes();
    final inspeccion = await inspeccionar(
      bytes,
      nombre: p.basename(ruta),
      fechaArchivo: (await archivo.stat()).modified,
    );
    return restaurar(inspeccion);
  }

  Future<Directory> _dirSeguridad() async {
    final base = await _documentos();
    final dir = Directory(p.join(base.path, 'respaldos_seguridad'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _limpiarJournal(String ruta) async {
    for (final sufijo in const ['-wal', '-shm', '-journal']) {
      final journal = File('$ruta$sufijo');
      try {
        if (await journal.exists()) await journal.delete();
      } catch (_) {
        // Ignorar.
      }
    }
  }

  void _validarCabecera(Uint8List bytes) {
    if (bytes.length < 100) {
      throw const FormatException(
        'El archivo está incompleto o no es una copia válida.',
      );
    }
    final cabecera = String.fromCharCodes(bytes.sublist(0, 16));
    if (cabecera != _cabecera) {
      throw const FormatException(
        'El archivo seleccionado no es una base de datos de Conwich.',
      );
    }
  }

  String _sha256(Uint8List bytes) => sha256.convert(bytes).toString();

  String _stamp(DateTime fecha) {
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${fecha.year}-${dos(fecha.month)}-${dos(fecha.day)}'
        '_${dos(fecha.hour)}-${dos(fecha.minute)}-${dos(fecha.second)}';
  }
}
