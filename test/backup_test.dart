import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:excel/excel.dart';

import 'package:test_code_02/core/auth_repository.dart';
import 'package:test_code_02/core/backup/backup_service.dart';
import 'package:test_code_02/core/backup/excel_exporter.dart';
import 'package:test_code_02/data/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Cada archivo de test usa su propia carpeta: los tests de Flutter se
    // ejecutan en paralelo y compartir el archivo bloquearía la base.
    final dir = await Directory.systemTemp.createTemp('sazon_db_');
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

  test('el primer acceso obliga a cambiar usuario y contraseña', () async {
    final auth = AuthRepository();
    final admin = (await auth.login('admin', '1234'))!;
    expect(admin.debeCambiarPassword, isTrue);

    // El nombre de fábrica no se puede reutilizar, ni con otra capitalización.
    expect(await auth.usuarioDisponible('admin'), isFalse);
    expect(await auth.usuarioDisponible('ADMIN'), isFalse);
    expect(await auth.usuarioDisponible('duenio'), isTrue);

    await auth.actualizarCredenciales(
      usuarioId: admin.id,
      usuario: 'duenio',
      password: 'claveSegura1',
    );

    expect(await auth.login('admin', '1234'), isNull);
    final nuevo = await auth.login('duenio', 'claveSegura1');
    expect(nuevo, isNotNull);
    expect(nuevo!.usuario, 'duenio');
    expect(nuevo.debeCambiarPassword, isFalse);
    expect(nuevo.esAdmin, isTrue);
  });

  test('la copia guarda su fecha y se puede restaurar', () async {
    final dir = await Directory.systemTemp.createTemp('sazon_backup_');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // El sistema limpia el temporal si algo queda abierto.
      }
    });
    final service = BackupService(
      rutaTemporal: () async => dir.path,
      rutaDocumentos: () async => dir.path,
    );

    final db = await AppDatabase.instance.database;
    await db.insert('categorias_producto', {'nombre': 'Bebidas'});
    final categoriasAntes = await db.query('categorias_producto');

    final copia = await service.crearCopia(motivo: 'manual');
    expect(await File(copia.ruta).exists(), isTrue);
    expect(copia.bytes.length, greaterThan(100));
    expect(copia.nombre, startsWith('conwich_respaldo_'));
    expect(copia.nombre, endsWith('.db'));

    final inspeccion = await service.inspeccionar(
      copia.bytes,
      nombre: copia.nombre,
    );
    expect(inspeccion.integridadOk, isTrue);
    expect(inspeccion.tieneMetadata, isTrue);
    expect(inspeccion.fechaRespaldo, isNotNull);
    expect(inspeccion.motivo, 'manual');
    expect(inspeccion.schemaVersion, AppDatabase.schemaVersion);
    expect(inspeccion.conteos['usuarios'], 1);
    expect(inspeccion.sha256.length, 64);
    expect(
      inspeccion.instalacionId,
      (await AppDatabase.instance.instalacionId),
    );

    // Se agrega información después del respaldo: al restaurar debe desaparecer.
    final db2 = await AppDatabase.instance.database;
    await db2.insert('categorias_producto', {'nombre': 'Postres'});
    final total = await db2.rawQuery(
      'SELECT COUNT(*) AS total FROM categorias_producto',
    );
    expect((total.first['total'] as num).toInt(), categoriasAntes.length + 1);

    final seguridad = await service.restaurar(inspeccion);
    expect(seguridad.tamanoBytes, greaterThan(0));

    final db3 = await AppDatabase.instance.database;
    final categorias = await db3.query('categorias_producto');
    expect(categorias.length, categoriasAntes.length);
    expect(
      categorias.any((categoria) => categoria['nombre'] == 'Bebidas'),
      isTrue,
    );
    expect(
      categorias.any((categoria) => categoria['nombre'] == 'Postres'),
      isFalse,
    );

    final copias = await service.listarCopiasSeguridad();
    expect(copias.length, 1);

    final meta = await AppDatabase.instance.leerAppMeta();
    expect(meta?['ultimo_respaldo_en'], isNotNull);
  });

  test(
    'la exportación a Excel genera una hoja por tabla sin datos sensibles',
    () async {
      final db = await AppDatabase.instance.database;
      await db.insert('categorias_producto', {'nombre': 'Bebidas'});
      await db.insert('productos', {
        'nombre': 'Café',
        'categoria_id': 1,
        'precio': 10,
        'tipo': 'DIRECTO',
        'creado_en': '2026-11-10 08:00:00',
      });

      final bytes = await ExcelExporter().generar();
      expect(bytes.length, greaterThan(1000));
      expect(bytes.sublist(0, 2), [0x50, 0x4B]); // Firma ZIP de .xlsx

      final libro = Excel.decodeBytes(bytes);
      expect(libro.tables.containsKey('Resumen'), isTrue);
      expect(libro.tables.containsKey('Productos'), isTrue);
      expect(libro.tables.containsKey('Pedidos'), isTrue);

      final encabezadosUsuarios = libro.tables['Usuarios']!.rows.first
          .map((celda) => celda?.value.toString())
          .toList();
      expect(encabezadosUsuarios.contains('password_hash'), isFalse);

      final encabezadosProductos = libro.tables['Productos']!.rows.first
          .map((celda) => celda?.value.toString())
          .toList();
      expect(encabezadosProductos.contains('imagen'), isFalse);
    },
  );

  test('rechaza archivos que no son una base SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('sazon_backup_');
    addTearDown(() => dir.delete(recursive: true));
    final service = BackupService(
      rutaTemporal: () async => dir.path,
      rutaDocumentos: () async => dir.path,
    );

    await expectLater(
      service.inspeccionar(
        Uint8List.fromList(List<int>.filled(200, 65)),
        nombre: 'falso.db',
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      service.inspeccionar(Uint8List.fromList([1, 2, 3]), nombre: 'corto.db'),
      throwsA(isA<FormatException>()),
    );
  });
}
