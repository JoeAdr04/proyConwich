import '../../data/database/app_database.dart';
import '../date_utils.dart';
import 'backup_service.dart';
import 'drive_folder_service.dart';

class DriveConfig {
  const DriveConfig({
    this.habilitado = false,
    this.carpetaUri,
    this.carpetaNombre,
    this.retencion = 30,
    this.alCerrarCaja = true,
    this.frecuencia = 'CADA_CIERRE',
    this.ultimoExito,
    this.ultimoError,
  });

  final bool habilitado;
  final String? carpetaUri;
  final String? carpetaNombre;
  final int retencion;
  final bool alCerrarCaja;
  final String frecuencia;
  final DateTime? ultimoExito;
  final String? ultimoError;

  bool get configurado =>
      habilitado && carpetaUri != null && carpetaUri!.isNotEmpty;

  DriveConfig copyWith({
    bool? habilitado,
    String? carpetaUri,
    String? carpetaNombre,
    int? retencion,
    bool? alCerrarCaja,
    String? frecuencia,
    DateTime? ultimoExito,
    String? ultimoError,
  }) => DriveConfig(
    habilitado: habilitado ?? this.habilitado,
    carpetaUri: carpetaUri ?? this.carpetaUri,
    carpetaNombre: carpetaNombre ?? this.carpetaNombre,
    retencion: retencion ?? this.retencion,
    alCerrarCaja: alCerrarCaja ?? this.alCerrarCaja,
    frecuencia: frecuencia ?? this.frecuencia,
    ultimoExito: ultimoExito ?? this.ultimoExito,
    ultimoError: ultimoError ?? this.ultimoError,
  );
}

class DriveBackupService {
  DriveBackupService({BackupService? backup, DriveFolderService? folder})
    : _backup = backup ?? BackupService(),
      _folder = folder ?? DriveFolderService();

  final BackupService _backup;
  final DriveFolderService _folder;
  bool _ocupado = false;

  static const frecuencias = <String>[
    'CADA_CIERRE',
    'DIARIO',
    'SEMANAL',
    'MENSUAL',
    'MANUAL',
  ];

  bool get disponible => _folder.disponible;

  Future<DriveConfig> leerConfig() async {
    final meta = await _backup.metaActual();
    return DriveConfig(
      habilitado: (meta?['drive_habilitado'] as num?)?.toInt() == 1,
      carpetaUri: meta?['drive_carpeta_uri'] as String?,
      carpetaNombre: meta?['drive_carpeta_nombre'] as String?,
      retencion: (meta?['drive_retencion'] as num?)?.toInt() ?? 30,
      alCerrarCaja:
          ((meta?['drive_al_cerrar_caja'] as num?)?.toInt() ?? 1) == 1,
      frecuencia: (meta?['drive_frecuencia'] as String?) ?? 'CADA_CIERRE',
      ultimoExito: parseSqlDateTime(meta?['drive_ultimo_exito'] as String?),
      ultimoError: meta?['drive_ultimo_error'] as String?,
    );
  }

  Future<void> guardarConfig({
    bool? habilitado,
    String? carpetaUri,
    String? carpetaNombre,
    int? retencion,
    bool? alCerrarCaja,
    String? frecuencia,
  }) async {
    final valores = <String, Object?>{};
    if (habilitado != null) valores['drive_habilitado'] = habilitado ? 1 : 0;
    if (carpetaUri != null) valores['drive_carpeta_uri'] = carpetaUri;
    if (carpetaNombre != null) valores['drive_carpeta_nombre'] = carpetaNombre;
    if (retencion != null) {
      valores['drive_retencion'] = retencion.clamp(1, 365);
    }
    if (alCerrarCaja != null) {
      valores['drive_al_cerrar_caja'] = alCerrarCaja ? 1 : 0;
    }
    if (frecuencia != null) valores['drive_frecuencia'] = frecuencia;
    await AppDatabase.instance.actualizarAppMeta(valores);
  }

  Future<void> marcarResultado({String? exito, String? error}) async {
    await AppDatabase.instance.actualizarAppMeta({
      'drive_ultimo_exito': exito,
      'drive_ultimo_error': error,
    });
  }

  Future<DriveFolder?> elegirCarpeta() async {
    final carpeta = await _folder.elegirCarpeta();
    if (carpeta == null) return null;
    await guardarConfig(
      habilitado: true,
      carpetaUri: carpeta.uri,
      carpetaNombre: carpeta.nombre,
    );
    return carpeta;
  }

  Future<bool> comprobarCarpeta() async {
    final config = await leerConfig();
    if (!config.configurado) return false;
    return _folder.tienePermiso(config.carpetaUri!);
  }

  /// Crea y sube una copia en este momento. Lanza un error si falta configurar
  /// la carpeta, el permiso o la escritura.
  Future<void> respaldarAhora({required String motivo}) async {
    if (_ocupado) {
      throw StateError('Ya hay un respaldo en curso.');
    }
    final config = await leerConfig();
    if (!config.configurado) {
      throw StateError('Primero elige una carpeta de Google Drive.');
    }
    final carpetaUri = config.carpetaUri!;
    if (!await _folder.tienePermiso(carpetaUri)) {
      throw StateError(
        'La app perdió el permiso de la carpeta. Vuelve a elegirla.',
      );
    }
    _ocupado = true;
    try {
      final copia = await _backup.crearCopia(motivo: motivo);
      await _folder.escribir(
        carpetaUri: carpetaUri,
        nombre: copia.nombre,
        bytes: copia.bytes,
      );
      await marcarResultado(exito: sqlNow(), error: null);
      await purgar(config.retencion);
    } catch (error) {
      await marcarResultado(
        exito: config.ultimoExito == null ? null : sqlDateTime(config.ultimoExito!),
        error: '$error',
      );
      rethrow;
    } finally {
      _ocupado = false;
    }
  }

  /// Respaldo automático. Devuelve `true` si subió la copia.
  Future<bool> respaldarSiCorresponde({required String motivo}) async {
    final config = await leerConfig();
    if (!config.configurado) return false;
    if (!_correspondePorFrecuencia(config, motivo)) return false;
    await respaldarAhora(motivo: motivo);
    return true;
  }

  Future<void> purgar(int retencion) async {
    final config = await leerConfig();
    if (!config.configurado) return;
    try {
      final archivos = await _folder.listar(config.carpetaUri!);
      final copias = archivos
          .where((archivo) => archivo.nombre.startsWith('conwich_respaldo_'))
          .toList()
        ..sort((a, b) {
          final fechaA = a.modificado;
          final fechaB = b.modificado;
          if (fechaA != null && fechaB != null) {
            return fechaB.compareTo(fechaA);
          }
          return b.nombre.compareTo(a.nombre);
        });
      final maximo = retencion.clamp(1, 365);
      for (final archivo in copias.skip(maximo)) {
        try {
          await _folder.borrar(archivo.uri);
        } catch (_) {
          // Si una copia no se puede borrar, se reintenta en el próximo purgado.
        }
      }
    } catch (_) {
      // La limpieza no debe impedir que el respaldo se considere exitoso.
    }
  }

  bool _correspondePorFrecuencia(DriveConfig config, String motivo) {
    final frecuencia = config.frecuencia;
    if (frecuencia == 'MANUAL') return false;
    if (motivo == 'cierre_caja') {
      if (!config.alCerrarCaja) return false;
      if (frecuencia == 'CADA_CIERRE') return true;
    } else {
      if (frecuencia == 'CADA_CIERRE') return false;
    }
    final ultimo = config.ultimoExito;
    if (ultimo == null) return true;
    final diferencia = DateTime.now().difference(ultimo);
    return switch (frecuencia) {
      'DIARIO' => diferencia.inHours >= 20,
      'SEMANAL' => diferencia.inDays >= 6,
      'MENSUAL' => diferencia.inDays >= 28,
      _ => true,
    };
  }
}
