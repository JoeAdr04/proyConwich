import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:test_code_02/core/backup/drive_backup_service.dart';
import 'package:test_code_02/core/backup/drive_folder_service.dart';
import 'package:test_code_02/core/date_utils.dart';
import 'package:test_code_02/data/database/app_database.dart';

class _FakeFolder extends DriveFolderService {
  final archivos = <DriveFile>[];

  @override
  bool get disponible => true;

  @override
  Future<bool> tienePermiso(String uri) async => true;

  @override
  Future<List<DriveFile>> listar(String carpetaUri) async =>
      List<DriveFile>.of(archivos);

  @override
  Future<void> borrar(String archivoUri) async {
    archivos.removeWhere((archivo) => archivo.uri == archivoUri);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('sazon_drive_');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  setUp(() async {
    await AppDatabase.instance.close();
    final path = join(await getDatabasesPath(), AppDatabase.nombreArchivo);
    await databaseFactory.deleteDatabase(path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    final path = join(await getDatabasesPath(), AppDatabase.nombreArchivo);
    await databaseFactory.deleteDatabase(path);
  });

  test('guarda la configuración y conserva solo las copias indicadas', () async {
    final fake = _FakeFolder();
    final drive = DriveBackupService(folder: fake);
    await drive.guardarConfig(
      habilitado: true,
      carpetaUri: 'content://drive/conwich',
      carpetaNombre: 'Conwich',
      retencion: 2,
      frecuencia: 'CADA_CIERRE',
      alCerrarCaja: true,
    );

    final config = await drive.leerConfig();
    expect(config.configurado, isTrue);
    expect(config.carpetaNombre, 'Conwich');
    expect(config.retencion, 2);
    expect(config.alCerrarCaja, isTrue);

    fake.archivos.addAll([
      DriveFile(
        uri: '1',
        nombre: 'conwich_respaldo_2026-11-10_10-00-00.db',
        tamano: 10,
        modificado: DateTime(2026, 11, 10, 10),
      ),
      DriveFile(
        uri: '2',
        nombre: 'conwich_respaldo_2026-11-11_10-00-00.db',
        tamano: 10,
        modificado: DateTime(2026, 11, 11, 10),
      ),
      DriveFile(
        uri: '3',
        nombre: 'conwich_respaldo_2026-11-12_10-00-00.db',
        tamano: 10,
        modificado: DateTime(2026, 11, 12, 10),
      ),
      DriveFile(
        uri: '4',
        nombre: 'conwich_respaldo_2026-11-13_10-00-00.db',
        tamano: 10,
        modificado: DateTime(2026, 11, 13, 10),
      ),
    ]);

    await drive.purgar(2);
    expect(fake.archivos.length, 2);
    expect(
      fake.archivos.map((archivo) => archivo.uri).toSet(),
      {'3', '4'},
    );
  });

  test('la frecuencia evita copias automáticas repetidas', () async {
    final fake = _FakeFolder();
    final drive = DriveBackupService(folder: fake);
    await drive.guardarConfig(
      habilitado: true,
      carpetaUri: 'content://drive/conwich',
      carpetaNombre: 'Conwich',
      retencion: 30,
      frecuencia: 'DIARIO',
      alCerrarCaja: true,
    );
    await drive.marcarResultado(exito: sqlNow(), error: null);
    expect(
      await drive.respaldarSiCorresponde(motivo: 'cierre_caja'),
      isFalse,
    );
    expect(fake.archivos, isEmpty);
  });
}
