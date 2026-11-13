import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DriveFolder {
  const DriveFolder({required this.uri, required this.nombre});

  final String uri;
  final String nombre;
}

class DriveFile {
  const DriveFile({
    required this.uri,
    required this.nombre,
    required this.tamano,
    this.modificado,
  });

  final String uri;
  final String nombre;
  final int tamano;
  final DateTime? modificado;
}

/// Acceso a una carpeta elegida con el selector de Android (SAF). Si el
/// usuario escoge una carpeta de Google Drive, los archivos se escriben ahí
/// sin depender de Google Cloud ni de una suscripción.
class DriveFolderService {
  static const _channel = MethodChannel('com.example.test_code_02/drive_folder');

  bool get disponible =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<DriveFolder?> elegirCarpeta() async {
    if (!disponible) return null;
    final resultado = await _channel.invokeMapMethod<String, Object?>(
      'pickFolder',
    );
    final uri = resultado?['uri'] as String?;
    if (uri == null || uri.isEmpty) return null;
    return DriveFolder(
      uri: uri,
      nombre: (resultado?['name'] as String?) ?? 'Carpeta de Drive',
    );
  }

  Future<bool> tienePermiso(String uri) async {
    if (!disponible) return false;
    return await _channel.invokeMethod<bool>('checkPermission', {
          'uri': uri,
        }) ??
        false;
  }

  Future<void> escribir({
    required String carpetaUri,
    required String nombre,
    required Uint8List bytes,
  }) async {
    if (!disponible) {
      throw UnsupportedError('El respaldo en Drive solo está disponible en Android.');
    }
    final ok = await _channel.invokeMethod<bool>('writeFile', {
      'uri': carpetaUri,
      'name': nombre,
      'bytes': bytes,
    });
    if (ok != true) {
      throw StateError('No se pudo escribir el respaldo en la carpeta elegida.');
    }
  }

  Future<List<DriveFile>> listar(String carpetaUri) async {
    if (!disponible) return const [];
    final filas = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'listFiles',
      {'uri': carpetaUri},
    );
    if (filas == null) return const [];
    return filas
        .map((fila) {
          final uri = fila['uri'] as String?;
          if (uri == null) return null;
          final millis = (fila['modified'] as num?)?.toInt();
          return DriveFile(
            uri: uri,
            nombre: (fila['name'] as String?) ?? '',
            tamano: (fila['size'] as num?)?.toInt() ?? 0,
            modificado: millis == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(millis),
          );
        })
        .whereType<DriveFile>()
        .toList();
  }

  Future<void> borrar(String archivoUri) async {
    if (!disponible) return;
    await _channel.invokeMethod<bool>('deleteFile', {'fileUri': archivoUri});
  }
}
