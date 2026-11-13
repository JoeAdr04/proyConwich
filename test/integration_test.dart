import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:test_code_02/core/auth_repository.dart';
import 'package:test_code_02/core/cash_repository.dart';
import 'package:test_code_02/core/catalog_repository.dart';
import 'package:test_code_02/core/menu_repository.dart';
import 'package:test_code_02/core/receipt_service.dart';
import 'package:test_code_02/core/report_repository.dart';
import 'package:test_code_02/core/sales_repository.dart';
import 'package:test_code_02/core/session.dart';
import 'package:test_code_02/data/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    await databaseFactory.deleteDatabase(path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    await databaseFactory.deleteDatabase(path);
  });

  test('flujo completo de caja, ventas, stock y reportes', () async {
    final auth = AuthRepository();
    expect(await auth.usaCredencialesPorDefecto(), isTrue);

    expect(await auth.login('admin', 'incorrecta'), isNull);
    final admin = (await auth.login('admin', '1234'))!;
    expect(admin.esAdmin, isTrue);
    expect(admin.usuario, 'admin');
    expect(admin.debeCambiarPassword, isTrue);

    await auth.guardarSesion(admin.id);
    expect((await auth.restaurarSesion())?.id, admin.id);
    await auth.cerrarSesion();
    expect(await auth.restaurarSesion(), isNull);

    await auth.saveUsuario(
      nombre: 'Cajera',
      usuario: 'cajera',
      perfil: Perfil.cajero,
      activo: true,
      permisos: Perfil.vistasPorDefecto[Perfil.cajero]!,
      password: 'caja123',
    );
    final cajera = (await auth.login('cajera', 'caja123'))!;
    expect(cajera.esAdmin, isFalse);
    expect(cajera.perfil, Perfil.cajero);
    expect(cajera.puede(Permiso.ventas), isTrue);
    expect(cajera.puede(Permiso.caja), isTrue);
    expect(cajera.puede(Permiso.agotamiento), isTrue);
    expect(cajera.puede(Permiso.menu), isFalse);
    expect(cajera.puede(Permiso.tablero), isFalse);
    expect(cajera.puede(Permiso.productos), isFalse);
    expect(cajera.puede(Permiso.insumos), isFalse);
    expect(cajera.puede(Permiso.usuarios), isFalse);
    expect(cajera.puede(Permiso.reportes), isFalse);

    await auth.saveUsuario(
      nombre: 'Vendedor',
      usuario: 'vendedor',
      perfil: Perfil.vendedor,
      activo: true,
      permisos: Perfil.vistasPorDefecto[Perfil.vendedor]!,
      password: 'vende123',
    );
    final vendedor = (await auth.login('vendedor', 'vende123'))!;
    expect(vendedor.puede(Permiso.ventas), isTrue);
    expect(vendedor.puede(Permiso.caja), isFalse);
    expect(vendedor.puede(Permiso.reportes), isFalse);
    expect(vendedor.permisos.length, 2);

    expect(await auth.verificarPassword(cajera.id, 'caja123'), isTrue);
    await auth.cambiarPassword(cajera.id, 'nueva123');
    expect(await auth.verificarPassword(cajera.id, 'caja123'), isFalse);
    expect(await auth.login('cajera', 'caja123'), isNull);
    expect((await auth.login('cajera', 'nueva123'))?.id, cajera.id);

    final catalog = CatalogRepository();
    await catalog.saveCategoria(
      const CategoriaProducto(
        nombre: 'BEBIDAS',
        color: 0xFF2563EB,
        siempreDisponible: false,
        orden: 1,
        activo: true,
      ),
    );
    await catalog.saveCategoria(
      const CategoriaProducto(
        nombre: 'ALMUERZOS',
        color: 0xFF0F766E,
        siempreDisponible: false,
        orden: 2,
        activo: true,
      ),
    );
    final categorias = await catalog.getCategorias();
    final bebidas = categorias.firstWhere((c) => c.nombre == 'BEBIDAS');
    final almuerzos = categorias.firstWhere((c) => c.nombre == 'ALMUERZOS');
    final unidades = await catalog.getUnidades();
    final unidad = unidades.firstWhere((u) => u.abreviatura == 'und');

    final papaId = await catalog.saveInsumo(
      Insumo(
        nombre: 'Papa',
        unidadId: unidad.id,
        unidadAbreviatura: unidad.abreviatura,
        stockMinimo: 5,
        costoPromedio: 3,
        activo: true,
        stock: 0,
      ),
    );
    final aceiteId = await catalog.saveInsumo(
      Insumo(
        nombre: 'Aceite',
        unidadId: unidad.id,
        unidadAbreviatura: unidad.abreviatura,
        stockMinimo: 0,
        costoPromedio: 0,
        activo: true,
        stock: 0,
      ),
    );

    // El stock se carga con ajustes manuales.
    await catalog.ajustarStockInsumo(
      insumoId: papaId,
      nuevoStock: 10,
      usuarioId: admin.id,
      motivo: 'Carga inicial',
    );
    await catalog.ajustarStockInsumo(
      insumoId: aceiteId,
      nuevoStock: 5,
      usuarioId: admin.id,
      motivo: 'Carga inicial',
    );
    expect(await catalog.getStockInsumo(papaId), 10);
    expect(await catalog.getStockInsumo(aceiteId), 5);

    final cocaId = await catalog.saveProducto(
      Producto(
        nombre: 'Coca Cola',
        categoriaId: bebidas.id!,
        categoriaNombre: bebidas.nombre,
        categoriaColor: bebidas.color,
        precio: 5,
        tipo: 'DIRECTO',
        stockMinimo: 2,
        costoUnitario: 3,
        activo: true,
        stock: 0,
      ),
    );
    final almuerzoId = await catalog.saveProducto(
      Producto(
        nombre: 'Almuerzo del día',
        categoriaId: almuerzos.id!,
        categoriaNombre: almuerzos.nombre,
        categoriaColor: almuerzos.color,
        precio: 15,
        tipo: 'PREPARADO',
        stockMinimo: 0,
        costoUnitario: 0,
        activo: true,
        stock: 0,
      ),
    );
    await catalog.ajustarStockProducto(
      productoId: cocaId,
      nuevoStock: 5,
      usuarioId: admin.id,
      motivo: 'Carga inicial',
    );
    expect(await catalog.getStockProducto(cocaId), 5);

    await catalog.saveRecetaCantidades(almuerzoId, {papaId: 0.5, aceiteId: 1});

    // Los productos directos activos se venden siempre.
    final directos = await catalog.getProductosDirectosActivos();
    expect(directos.length, 1);
    expect(directos.first.nombre, 'Coca Cola');
    final preparados = await catalog.getProductosPreparadosActivos();
    expect(preparados.length, 1);
    expect(preparados.first.nombre, 'Almuerzo del día');

    final menuRepo = MenuRepository();
    final menu = await menuRepo.crearMenu(DateTime.now(), 'ALMUERZO', admin.id);
    await menuRepo.agregarProducto(menu.id, almuerzoId);
    await menuRepo.habilitar(menu.id);
    expect(
      (await menuRepo.getMenuHabilitado(DateTime.now(), 'ALMUERZO')).length,
      1,
    );

    final cash = CashRepository();
    final caja = await cash.abrirCaja(
      fecha: DateTime.now(),
      fondoInicial: 100,
      usuarioId: admin.id,
    );
    expect(caja.numeroTurno, 1);
    expect((await cash.getCajaAbierta())?.id, caja.id);

    final sales = SalesRepository();
    final pedidoId = await sales.crearPedido(
      usuarioId: admin.id,
      cajaId: caja.id,
      menuDiaId: menu.id,
      referencia: 'Mesa 3',
      lineas: [
        CartLine(
          productoId: almuerzoId,
          menuDiaItemId: (await menuRepo.getItems(menu.id)).first.id,
          nombre: 'Almuerzo del día',
          precio: 15,
          cantidad: 2,
          tipo: 'PREPARADO',
        ),
        CartLine(
          productoId: cocaId,
          nombre: 'Coca Cola',
          precio: 5,
          cantidad: 1,
          tipo: 'DIRECTO',
        ),
      ],
      pagos: const [
        PagoInput(metodo: 'QR', monto: 30),
        PagoInput(metodo: 'EFECTIVO', monto: 5),
      ],
    );
    final detalle = await sales.getPedido(pedidoId);
    expect(detalle.pedido.estadoPago, 'PAGADO');
    expect(detalle.pedido.total, 35);
    expect(detalle.pagos.length, 2);
    expect(await catalog.getStockInsumo(papaId), 9);
    expect(await catalog.getStockInsumo(aceiteId), 3);
    expect(await catalog.getStockProducto(cocaId), 4);

    var resumenCaja = await cash.getResumen(caja.id);
    expect(resumenCaja.ventasEfectivo, 5);
    expect(resumenCaja.ventasQr, 30);
    expect(resumenCaja.esperadoEfectivo, 105);
    expect(resumenCaja.esperadoQr, 30);

    // Salida de caja.
    await cash.registrarSalida(
      cajaId: caja.id,
      usuarioId: admin.id,
      monto: 10,
      metodoPago: 'EFECTIVO',
      descripcion: 'Luz',
    );
    resumenCaja = await cash.getResumen(caja.id);
    expect(resumenCaja.salidasEfectivo, 10);
    expect(resumenCaja.esperadoEfectivo, 95);

    final reports = ReportRepository();
    final hoy = DateTime.now();
    final inicio = DateTime(hoy.year, hoy.month, hoy.day);
    final fin = inicio.add(const Duration(days: 1));
    var resumen = await reports.getResumen(inicio, fin);
    expect(resumen.ventas, 35);
    expect(resumen.cobros, 35);
    // Gasto en insumos: la carga inicial de stock (10 und de Papa × Bs 3).
    expect(resumen.gastoInsumos, 30);
    expect(resumen.salidas, 10);
    expect(
      resumen.ganancia,
      resumen.ventas - resumen.gastoInsumos - resumen.salidas,
    );
    final productos = await reports.getProductos(inicio, fin);
    expect(productos.length, 2);
    final pedidosReporte = await reports.getPedidos(inicio, fin);
    expect(pedidosReporte.length, 1);
    expect(pedidosReporte.first.id, pedidoId);
    expect(pedidosReporte.first.total, 35);
    expect(pedidosReporte.first.efectivo, 5);
    expect(pedidosReporte.first.qr, 30);
    expect(pedidosReporte.first.numeroTurno, 1);
    final salidas = await reports.getSalidasPorMotivo(inicio, fin);
    expect(salidas.length, 1);
    expect(salidas.first.nombre, 'Luz');
    final inventarioReporte = await reports.getInventario();
    expect(inventarioReporte.length, 3);

    // Ajuste manual de stock.
    await catalog.ajustarStockInsumo(
      insumoId: papaId,
      nuevoStock: 8,
      usuarioId: admin.id,
      motivo: 'Ajuste manual',
    );
    expect(await catalog.getStockInsumo(papaId), 8);

    await sales.anularPedido(pedidoId);
    expect(await catalog.getStockProducto(cocaId), 5);
    final resumenAnulado = await reports.getResumen(inicio, fin);
    expect(resumenAnulado.ventas, 0);
    expect(resumenAnulado.cobros, 0);
    expect(
      resumenAnulado.ganancia,
      resumenAnulado.ventas -
          resumenAnulado.gastoInsumos -
          resumenAnulado.salidas,
    );

    final pendienteId = await sales.crearPedido(
      usuarioId: admin.id,
      cajaId: caja.id,
      referencia: 'Mesa 5',
      lineas: [
        CartLine(
          productoId: cocaId,
          nombre: 'Coca Cola',
          precio: 5,
          cantidad: 1,
          tipo: 'DIRECTO',
        ),
      ],
      pagos: const [],
    );
    expect((await sales.getPedido(pendienteId)).pedido.estadoPago, 'PENDIENTE');
    expect(await catalog.getStockProducto(cocaId), 4);

    await cash.cerrarCaja(
      cajaId: caja.id,
      efectivoContado: 95,
      qrVerificado: 30,
      usuarioId: admin.id,
    );
    expect(await cash.getCajaAbierta(), isNull);
    final menuTrasCierre = await menuRepo.getMenu(DateTime.now(), 'ALMUERZO');
    expect(menuTrasCierre?.estado, 'HABILITADO');

    final nuevaCaja = await cash.abrirCaja(
      fecha: DateTime.now(),
      fondoInicial: 50,
      usuarioId: admin.id,
    );
    expect(nuevaCaja.numeroTurno, 2);
    await expectLater(
      sales.agregarPagos(
        pedidoId: pendienteId,
        usuarioId: admin.id,
        cajaId: caja.id,
        pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 5)],
      ),
      throwsA(isA<StateError>()),
    );
    await sales.agregarPagos(
      pedidoId: pendienteId,
      usuarioId: admin.id,
      cajaId: nuevaCaja.id,
      pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 5)],
    );
    expect((await sales.getPedido(pendienteId)).pedido.estadoPago, 'PAGADO');
    final resumenNuevaCaja = await cash.getResumen(nuevaCaja.id);
    expect(resumenNuevaCaja.ventasEfectivo, 5);
    expect(resumenNuevaCaja.esperadoEfectivo, 55);

    final resumenFinal = await reports.getResumen(inicio, fin);
    expect(resumenFinal.ventas, 5);
    expect(resumenFinal.cobros, 5);
    expect(
      resumenFinal.ganancia,
      resumenFinal.ventas - resumenFinal.gastoInsumos - resumenFinal.salidas,
    );

    final usuarios = await auth.getUsuarios();
    expect(usuarios.length, 3);
    final adminGuardado = usuarios.firstWhere((u) => u.usuario == 'admin');
    expect(adminGuardado.perfil, Perfil.admin);
    expect(adminGuardado.permisos.contains(Permiso.reportes), isTrue);
    expect(adminGuardado.permisos.length, Permiso.todos.length);
    final cajeraGuardada = usuarios.firstWhere((u) => u.usuario == 'cajera');
    expect(cajeraGuardada.perfil, Perfil.cajero);
    expect(cajeraGuardada.permisos.contains(Permiso.reportes), isFalse);
    expect(cajeraGuardada.permisos.contains(Permiso.ventas), isTrue);
    final vendedorGuardado = usuarios.firstWhere(
      (u) => u.usuario == 'vendedor',
    );
    expect(vendedorGuardado.permisos.contains(Permiso.caja), isFalse);
  });

  test('ninguna pantalla devuelve un Future a setState', () {
    // Un setState con un callback que devuelve un Future hace que Flutter
    // lance "setState() callback argument returned a Future" y la pantalla
    // no se refresque. Por eso _reload debe ser void.
    final archivos = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((archivo) => archivo.path.endsWith('.dart'));
    for (final archivo in archivos) {
      final contenido = archivo.readAsStringSync();
      expect(
        contenido.contains('=> _future ='),
        isFalse,
        reason:
            '${archivo.path} usa una función flecha que devuelve el Future; '
            'déjala con llaves para que devuelva void.',
      );
    }
  });

  test('migración desde la versión 2 conserva los datos', () async {
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    // Base vieja: mismo esquema sin la tabla de ajustes de stock.
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE usuarios (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nombre TEXT NOT NULL,
              usuario TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              rol TEXT NOT NULL CHECK (rol IN ('ADMIN','CAJERO')),
              turno_asignado TEXT CHECK (turno_asignado IN ('MAÑANA','TARDE','AMBOS')),
              sueldo_base REAL NOT NULL DEFAULT 0,
              activo INTEGER NOT NULL DEFAULT 1,
              creado_en TEXT NOT NULL
            )
          ''');
          await db.insert('usuarios', {
            'nombre': 'Administrador',
            'usuario': 'admin',
            'password_hash': hashPassword('1234'),
            'rol': 'ADMIN',
            'turno_asignado': 'AMBOS',
            'sueldo_base': 0,
            'activo': 1,
            'creado_en': '2026-01-01 08:00:00',
          });
        },
      ),
    );
    await legacy.close();

    final db = await AppDatabase.instance.database;
    final version = await db.rawQuery('PRAGMA user_version');
    expect(
      (version.first['user_version'] as num).toInt(),
      AppDatabase.schemaVersion,
    );
    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'ajustes_stock'",
    );
    expect(tablas.length, 1);
    final columnas = await db.rawQuery('PRAGMA table_info(usuarios)');
    expect(columnas.any((c) => c['name'] == 'perfil'), isTrue);
    expect(columnas.any((c) => c['name'] == 'debe_cambiar_password'), isTrue);
    final meta = await AppDatabase.instance.leerAppMeta();
    expect(meta, isNotNull);
    expect((meta!['instalacion_id'] as String).length, 36);

    final auth = AuthRepository();
    final admin = await auth.login('admin', '1234');
    expect(admin, isNotNull);
    expect(admin!.esAdmin, isTrue);
    expect(admin.perfil, Perfil.admin);
    expect(admin.debeCambiarPassword, isTrue);
    expect((await auth.getUsuarios()).length, 1);

    final catalog = CatalogRepository();
    final unidades = await catalog.getUnidades();
    expect(unidades.isNotEmpty, isTrue);
  });

  test(
    'venta directa desde insumos crea producto con receta de 1 unidad',
    () async {
      final auth = AuthRepository();
      final admin = (await auth.login('admin', '1234'))!;
      final catalog = CatalogRepository();
      await catalog.saveCategoria(
        const CategoriaProducto(
          nombre: 'BEBIDAS',
          color: 0xFF2563EB,
          siempreDisponible: false,
          orden: 1,
          activo: true,
        ),
      );
      final unidades = await catalog.getUnidades();
      final bebidas = (await catalog.getCategorias()).firstWhere(
        (categoria) => categoria.nombre == 'BEBIDAS',
      );
      final litro = unidades.firstWhere((u) => u.abreviatura == 'L');
      final mililitro = unidades.firstWhere((u) => u.abreviatura == 'ml');
      expect(litro.familia, 'VOLUMEN');
      expect(litro.factorBase, 1000);
      expect(mililitro.factorBase, 1);

      final insumoId = await catalog.saveInsumo(
        Insumo(
          nombre: 'Leche',
          unidadId: litro.id,
          unidadAbreviatura: litro.abreviatura,
          unidadNombre: litro.nombre,
          unidadFamilia: litro.familia,
          unidadFactorBase: litro.factorBase,
          stockMinimo: 0,
          costoPromedio: 2,
          activo: true,
          stock: 0,
          ventaDirecta: true,
          precioVenta: 5,
          categoriaVentaDirectaId: bebidas.id,
          imagen: Uint8List.fromList([1, 2, 3, 4]),
        ),
      );
      var insumo = (await catalog.getInsumo(insumoId))!;
      expect(insumo.productoId, isNotNull);
      final producto = (await catalog.getProducto(insumo.productoId!))!;
      expect(producto.precio, 5);
      expect(producto.esVentaDirecta, isTrue);
      expect(producto.categoriaId, bebidas.id);
      expect(producto.imagen, isNotNull);

      final receta = await catalog.getReceta(producto.id!);
      expect(receta.length, 1);
      expect(receta.first.insumoId, insumoId);
      expect(receta.first.cantidad, 1);

      await catalog.ajustarStockInsumo(
        insumoId: insumoId,
        nuevoStock: 30,
        usuarioId: admin.id,
        motivo: 'Carga inicial',
      );
      final cash = CashRepository();
      final caja = await cash.abrirCaja(
        fecha: DateTime.now(),
        fondoInicial: 0,
        usuarioId: admin.id,
      );
      final sales = SalesRepository();
      await sales.crearPedido(
        usuarioId: admin.id,
        cajaId: caja.id,
        lineas: [
          CartLine(
            productoId: producto.id!,
            nombre: producto.nombre,
            precio: 5,
            cantidad: 2,
            tipo: 'PREPARADO',
          ),
        ],
        pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 10)],
      );
      expect(await catalog.getStockInsumo(insumoId), 28);

      // Al apagar la venta directa el producto se desactiva, no se borra.
      insumo = (await catalog.getInsumo(insumoId))!;
      await catalog.saveInsumo(
        Insumo(
          id: insumo.id,
          nombre: insumo.nombre,
          unidadId: insumo.unidadId,
          unidadAbreviatura: insumo.unidadAbreviatura,
          unidadNombre: insumo.unidadNombre,
          unidadFamilia: insumo.unidadFamilia,
          unidadFactorBase: insumo.unidadFactorBase,
          stockMinimo: insumo.stockMinimo,
          costoPromedio: insumo.costoPromedio,
          activo: insumo.activo,
          stock: insumo.stock,
          ventaDirecta: false,
          productoId: insumo.productoId,
          categoriaVentaDirectaId: insumo.categoriaVentaDirectaId,
        ),
      );
      expect((await catalog.getProducto(producto.id!))!.activo, isFalse);
    },
  );

  test('el menú reemplaza sus platos y conserva el orden elegido', () async {
    final auth = AuthRepository();
    final admin = (await auth.login('admin', '1234'))!;
    final catalog = CatalogRepository();
    await catalog.saveCategoria(
      const CategoriaProducto(
        nombre: 'ALMUERZOS',
        color: 0xFF0F766E,
        siempreDisponible: false,
        orden: 1,
        activo: true,
      ),
    );
    final categoria = (await catalog.getCategorias()).first;
    final primero = await catalog.saveProducto(
      Producto(
        nombre: 'Sopa',
        categoriaId: categoria.id!,
        categoriaNombre: categoria.nombre,
        categoriaColor: categoria.color,
        precio: 8,
        tipo: 'PREPARADO',
        stockMinimo: 0,
        costoUnitario: 0,
        activo: true,
        stock: 0,
      ),
    );
    final segundo = await catalog.saveProducto(
      Producto(
        nombre: 'Segundo',
        categoriaId: categoria.id!,
        categoriaNombre: categoria.nombre,
        categoriaColor: categoria.color,
        precio: 12,
        tipo: 'PREPARADO',
        stockMinimo: 0,
        costoUnitario: 0,
        activo: true,
        stock: 0,
      ),
    );
    final menuRepo = MenuRepository();
    final menu = await menuRepo.crearMenu(DateTime.now(), 'ALMUERZO', admin.id);
    await menuRepo.reemplazarItems(menu.id, [segundo, primero]);
    final items = await menuRepo.getItems(menu.id);
    expect(items.length, 2);
    expect(items.first.productoId, segundo);
    expect(items.last.productoId, primero);

    await menuRepo.reemplazarItems(menu.id, [primero]);
    final recortado = await menuRepo.getItems(menu.id);
    expect(recortado.length, 1);
    expect(recortado.first.productoId, primero);
  });

  test('migración de productos directos a insumos con receta', () async {
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE usuarios (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nombre TEXT NOT NULL,
              usuario TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              rol TEXT NOT NULL CHECK (rol IN ('ADMIN','CAJERO')),
              turno_asignado TEXT CHECK (turno_asignado IN ('MAÑANA','TARDE','AMBOS')),
              sueldo_base REAL NOT NULL DEFAULT 0,
              activo INTEGER NOT NULL DEFAULT 1,
              creado_en TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE categorias_producto (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nombre TEXT NOT NULL UNIQUE,
              color INTEGER NOT NULL DEFAULT 4280391418,
              siempre_disponible INTEGER NOT NULL DEFAULT 0,
              orden INTEGER NOT NULL DEFAULT 0,
              activo INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await db.execute('''
            CREATE TABLE productos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nombre TEXT NOT NULL UNIQUE,
              categoria_id INTEGER NOT NULL,
              descripcion TEXT,
              precio REAL NOT NULL DEFAULT 0,
              imagen BLOB,
              tipo TEXT NOT NULL CHECK (tipo IN ('DIRECTO','PREPARADO')),
              stock_minimo REAL NOT NULL DEFAULT 0,
              costo_unitario REAL NOT NULL DEFAULT 0,
              activo INTEGER NOT NULL DEFAULT 1,
              creado_en TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE ajustes_stock (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              fecha TEXT NOT NULL,
              insumo_id INTEGER,
              producto_id INTEGER,
              cantidad REAL NOT NULL DEFAULT 0,
              motivo TEXT,
              usuario_id INTEGER NOT NULL
            )
          ''');
          await db.insert('usuarios', {
            'nombre': 'Administrador',
            'usuario': 'admin',
            'password_hash': hashPassword('1234'),
            'rol': 'ADMIN',
            'turno_asignado': 'AMBOS',
            'sueldo_base': 0,
            'activo': 1,
            'creado_en': '2026-01-01 08:00:00',
          });
          await db.insert('categorias_producto', {
            'nombre': 'Bebidas',
            'color': 0xFF2563EB,
            'siempre_disponible': 0,
            'orden': 1,
            'activo': 1,
          });
          await db.insert('productos', {
            'nombre': 'Coca Cola',
            'categoria_id': 1,
            'precio': 5,
            'tipo': 'DIRECTO',
            'stock_minimo': 2,
            'costo_unitario': 3,
            'activo': 1,
            'creado_en': '2026-01-01 08:00:00',
          });
          await db.insert('ajustes_stock', {
            'fecha': '2026-01-01 08:00:00',
            'insumo_id': null,
            'producto_id': 1,
            'cantidad': 5,
            'motivo': 'Carga inicial',
            'usuario_id': 1,
          });
        },
      ),
    );
    await legacy.close();

    final db = await AppDatabase.instance.database;
    final version = await db.rawQuery('PRAGMA user_version');
    expect(
      (version.first['user_version'] as num).toInt(),
      AppDatabase.schemaVersion,
    );

    final catalog = CatalogRepository();
    final producto = (await catalog.getProducto(1))!;
    expect(producto.tipo, 'PREPARADO');
    expect(producto.esVentaDirecta, isTrue);
    final insumo = (await catalog.getInsumos()).firstWhere(
      (item) => item.productoId == 1,
    );
    expect(insumo.ventaDirecta, isTrue);
    expect(insumo.stock, 5);
    expect(insumo.precioVenta, 5);
    final receta = await catalog.getReceta(1);
    expect(receta.length, 1);
    expect(receta.first.cantidad, 1);
  });

  test('migración de turnos de caja conserva pedidos y pagos', () async {
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE usuarios (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nombre TEXT NOT NULL,
              usuario TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              rol TEXT NOT NULL CHECK (rol IN ('ADMIN','CAJERO')),
              turno_asignado TEXT CHECK (turno_asignado IN ('MAÑANA','TARDE','AMBOS')),
              sueldo_base REAL NOT NULL DEFAULT 0,
              activo INTEGER NOT NULL DEFAULT 1,
              creado_en TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE categorias_producto (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nombre TEXT NOT NULL UNIQUE,
              color INTEGER NOT NULL DEFAULT 4280391418,
              siempre_disponible INTEGER NOT NULL DEFAULT 0,
              orden INTEGER NOT NULL DEFAULT 0,
              activo INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await db.execute('''
            CREATE TABLE cajas (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              fecha TEXT NOT NULL,
              turno TEXT NOT NULL CHECK (turno IN ('MAÑANA','TARDE')),
              usuario_apertura_id INTEGER NOT NULL,
              usuario_cierre_id INTEGER,
              fecha_apertura TEXT NOT NULL,
              fecha_cierre TEXT,
              fondo_inicial REAL NOT NULL DEFAULT 0,
              efectivo_contado REAL,
              qr_verificado REAL,
              estado TEXT NOT NULL DEFAULT 'ABIERTA' CHECK (estado IN ('ABIERTA','CERRADA')),
              observacion TEXT,
              UNIQUE (fecha, turno)
            )
          ''');
          await db.execute('''
            CREATE TABLE pedidos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              referencia TEXT,
              usuario_id INTEGER NOT NULL,
              caja_id INTEGER NOT NULL,
              menu_dia_id INTEGER,
              fecha TEXT NOT NULL,
              estado_pago TEXT NOT NULL DEFAULT 'PENDIENTE',
              estado_entrega TEXT NOT NULL DEFAULT 'PENDIENTE',
              total REAL NOT NULL DEFAULT 0,
              observacion TEXT,
              FOREIGN KEY (caja_id) REFERENCES cajas(id)
            )
          ''');
          await db.execute('''
            CREATE TABLE pagos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              pedido_id INTEGER NOT NULL,
              caja_id INTEGER NOT NULL,
              usuario_id INTEGER NOT NULL,
              fecha TEXT NOT NULL,
              monto REAL NOT NULL,
              metodo_pago TEXT NOT NULL,
              estado TEXT NOT NULL DEFAULT 'CONFIRMADO',
              referencia TEXT,
              FOREIGN KEY (caja_id) REFERENCES cajas(id)
            )
          ''');
          await db.insert('usuarios', {
            'nombre': 'Administrador',
            'usuario': 'admin',
            'password_hash': hashPassword('1234'),
            'rol': 'ADMIN',
            'turno_asignado': 'AMBOS',
            'sueldo_base': 0,
            'activo': 1,
            'creado_en': '2026-01-01 08:00:00',
          });
          await db.insert('cajas', {
            'fecha': '2026-01-01',
            'turno': 'TARDE',
            'usuario_apertura_id': 1,
            'fecha_apertura': '2026-01-01 14:00:00',
            'fondo_inicial': 100,
            'estado': 'CERRADA',
          });
          await db.insert('pedidos', {
            'usuario_id': 1,
            'caja_id': 1,
            'fecha': '2026-01-01 15:00:00',
            'estado_pago': 'PAGADO',
            'estado_entrega': 'ENTREGADO',
            'total': 20,
          });
          await db.insert('pagos', {
            'pedido_id': 1,
            'caja_id': 1,
            'usuario_id': 1,
            'fecha': '2026-01-01 15:00:00',
            'monto': 20,
            'metodo_pago': 'EFECTIVO',
            'estado': 'CONFIRMADO',
          });
        },
      ),
    );
    await legacy.close();

    final db = await AppDatabase.instance.database;
    final foreignKeys = await db.rawQuery('PRAGMA foreign_keys');
    expect((foreignKeys.first.values.first as num).toInt(), 1);
    final columnasCajas = await db.rawQuery('PRAGMA table_info(cajas)');
    expect(columnasCajas.any((c) => c['name'] == 'numero_turno'), isTrue);
    expect(columnasCajas.any((c) => c['name'] == 'turno'), isFalse);
    final cajas = await db.query('cajas');
    expect(cajas.length, 1);
    expect(cajas.first['numero_turno'], 2);
    expect((await db.query('pedidos')).length, 1);
    expect((await db.query('pagos')).length, 1);
  });

  test('genera la nota de venta en PDF', () async {
    final auth = AuthRepository();
    await auth.login('admin', '1234');
    final detalle = PedidoDetalle(
      pedido: Pedido(
        id: 1,
        referencia: 'Mesa 1',
        estadoPago: 'PAGADO',
        estadoEntrega: 'ENTREGADO',
        total: 35,
        pagado: 35,
        fecha: '2026-01-01 12:00:00',
        usuarioNombre: 'Administrador',
        cajaId: 1,
      ),
      lineas: const [
        PedidoLinea(
          id: 1,
          productoId: 1,
          nombre: 'Almuerzo completo',
          cantidad: 2,
          precioUnitario: 15,
          subtotal: 30,
        ),
        PedidoLinea(
          id: 2,
          productoId: 2,
          nombre: 'Refresco',
          cantidad: 1,
          precioUnitario: 5,
          subtotal: 5,
        ),
      ],
      pagos: const [
        Pago(
          id: 1,
          monto: 30,
          metodo: 'QR',
          estado: 'CONFIRMADO',
          fecha: '2026-01-01 12:00:00',
        ),
        Pago(
          id: 2,
          monto: 5,
          metodo: 'EFECTIVO',
          estado: 'CONFIRMADO',
          fecha: '2026-01-01 12:00:00',
        ),
      ],
    );
    final bytes = await ReceiptService().generarNotaVenta(
      detalle: detalle,
      turno: 'Turno 1',
      cajero: 'Administrador',
    );
    expect(bytes.length, greaterThan(1000));
  });

  test('las categorías nuevas se guardan en mayúsculas', () async {
    await AuthRepository().login('admin', '1234');
    final catalog = CatalogRepository();
    await catalog.saveCategoria(
      const CategoriaProducto(
        nombre: 'Postres',
        color: 0xFFDB2777,
        siempreDisponible: false,
        orden: 20,
        activo: true,
      ),
    );
    final categorias = await catalog.getCategorias();
    expect(
      categorias.any((categoria) => categoria.nombre == 'POSTRES'),
      isTrue,
    );
    expect(
      categorias.any((categoria) => categoria.nombre == 'Postres'),
      isFalse,
    );
  });

  test(
    'la migración a v9 convierte categorías existentes a mayúsculas',
    () async {
      final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 8,
          onCreate: (db, version) async {
            await db.execute('''
            CREATE TABLE categorias_producto (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nombre TEXT NOT NULL UNIQUE,
              color INTEGER NOT NULL DEFAULT 4280391418,
              siempre_disponible INTEGER NOT NULL DEFAULT 0,
              orden INTEGER NOT NULL DEFAULT 0,
              activo INTEGER NOT NULL DEFAULT 1
            )
          ''');
            await db.insert('categorias_producto', {
              'nombre': 'Postres',
              'color': 0xFF2563EB,
            });
          },
        ),
      );
      await legacy.close();

      final db = await AppDatabase.instance.database;
      final categorias = await db.query('categorias_producto');
      expect(
        categorias.any((categoria) => categoria['nombre'] == 'POSTRES'),
        isTrue,
      );
      expect(
        categorias.any((categoria) => categoria['nombre'] == 'Postres'),
        isFalse,
      );
      expect(
        categorias.any(
          (categoria) => categoria['nombre'] == 'ALMUERZO COMPLETO',
        ),
        isFalse,
      );
      expect(
        categorias.any((categoria) => categoria['nombre'] == 'SOPA'),
        isFalse,
      );
      expect(
        categorias.any((categoria) => categoria['nombre'] == 'SEGUNDO'),
        isFalse,
      );
    },
  );

  test('el menú agrega y quita platos de forma inmediata', () async {
    final auth = AuthRepository();
    final admin = (await auth.login('admin', '1234'))!;
    final catalog = CatalogRepository();
    await catalog.saveCategoria(
      const CategoriaProducto(
        nombre: 'ALMUERZOS',
        color: 0xFF0F766E,
        siempreDisponible: false,
        orden: 1,
        activo: true,
      ),
    );
    final categoria = (await catalog.getCategorias()).firstWhere(
      (item) => item.nombre == 'ALMUERZOS',
    );
    final productoId = await catalog.saveProducto(
      Producto(
        nombre: 'Plato de prueba',
        categoriaId: categoria.id!,
        categoriaNombre: categoria.nombre,
        categoriaColor: categoria.color,
        precio: 10,
        tipo: 'PREPARADO',
        stockMinimo: 0,
        costoUnitario: 0,
        activo: true,
        stock: 0,
      ),
    );
    final menuRepo = MenuRepository();
    final fecha = DateTime.now();
    final menu = await menuRepo.crearMenu(fecha, 'ALMUERZO', admin.id);
    await menuRepo.agregarProducto(menu.id, productoId);
    var items = await menuRepo.getItems(menu.id);
    expect(items.length, 1);
    expect(items.first.productoId, productoId);
    await menuRepo.quitarItem(items.first.id);
    items = await menuRepo.getItems(menu.id);
    expect(items, isEmpty);
    await menuRepo.agregarProducto(menu.id, productoId);
    items = await menuRepo.getItems(menu.id);
    expect(items.length, 1);
  });

  test('las categorías base son planas y usan los nombres nuevos', () async {
    await AuthRepository().login('admin', '1234');
    final catalog = CatalogRepository();
    final categorias = await catalog.getCategorias();
    final nombres = categorias.map((categoria) => categoria.nombre).toList();
    expect(
      nombres,
      containsAll([
        'PLATOS SUELTOS',
        'SOPAS',
        'BEBIDAS CALIENTES',
        'REFRESCOS',
        'FRAPPES',
      ]),
    );
    expect(nombres, isNot(contains('ALMUERZO COMPLETO')));
    expect(nombres, isNot(contains('SOPA')));
    expect(nombres, isNot(contains('SEGUNDO')));
    expect(categorias.every((categoria) => categoria.parentId == null), isTrue);
  });

  test('un admin puede elevar la sesión con su contraseña', () async {
    final auth = AuthRepository();
    final admin = (await auth.login('admin', '1234'))!;
    expect(await auth.loginAdminPorPassword('incorrecta'), isNull);
    final elevado = await auth.loginAdminPorPassword('1234');
    expect(elevado, isNotNull);
    expect(elevado!.id, admin.id);
    expect(elevado.esAdmin, isTrue);
  });

  test('la migración cambia el estado PUBLICADO por HABILITADO', () async {
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    // Base vieja: menús con el estado PUBLICADO y la columna publicado_en.
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE usuarios (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nombre TEXT NOT NULL,
              usuario TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              rol TEXT NOT NULL CHECK (rol IN ('ADMIN','CAJERO')),
              turno_asignado TEXT CHECK (turno_asignado IN ('MAÑANA','TARDE','AMBOS')),
              sueldo_base REAL NOT NULL DEFAULT 0,
              activo INTEGER NOT NULL DEFAULT 1,
              creado_en TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE menus_dia (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              fecha TEXT NOT NULL,
              tipo TEXT NOT NULL CHECK (tipo IN ('DESAYUNO','ALMUERZO')),
              estado TEXT NOT NULL DEFAULT 'BORRADOR' CHECK (estado IN ('BORRADOR','PUBLICADO','CERRADO')),
              usuario_id INTEGER NOT NULL,
              observacion TEXT,
              publicado_en TEXT,
              creado_en TEXT NOT NULL,
              UNIQUE (fecha, tipo),
              FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
            )
          ''');
          await db.execute('''
            CREATE TABLE menu_dia_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              menu_dia_id INTEGER NOT NULL,
              producto_id INTEGER NOT NULL,
              disponible INTEGER NOT NULL DEFAULT 1,
              motivo_agotado TEXT,
              orden INTEGER NOT NULL DEFAULT 0,
              UNIQUE (menu_dia_id, producto_id),
              FOREIGN KEY (menu_dia_id) REFERENCES menus_dia(id)
            )
          ''');
          await db.insert('usuarios', {
            'nombre': 'Administrador',
            'usuario': 'admin',
            'password_hash': hashPassword('1234'),
            'rol': 'ADMIN',
            'turno_asignado': 'AMBOS',
            'sueldo_base': 0,
            'activo': 1,
            'creado_en': '2026-01-01 08:00:00',
          });
          await db.insert('menus_dia', {
            'fecha': '2026-01-01',
            'tipo': 'ALMUERZO',
            'estado': 'PUBLICADO',
            'usuario_id': 1,
            'observacion': 'Con sopa',
            'publicado_en': '2026-01-01 08:30:00',
            'creado_en': '2026-01-01 08:00:00',
          });
          await db.insert('menus_dia', {
            'fecha': '2025-12-31',
            'tipo': 'DESAYUNO',
            'estado': 'BORRADOR',
            'usuario_id': 1,
            'creado_en': '2025-12-31 08:00:00',
          });
          await db.insert('menu_dia_items', {
            'menu_dia_id': 1,
            'producto_id': 1,
            'disponible': 1,
            'orden': 1,
          });
        },
      ),
    );
    await legacy.close();

    final db = await AppDatabase.instance.database;
    final menus = await db.query('menus_dia', orderBy: 'id');
    expect(menus.length, 2);
    expect(menus.first['estado'], 'HABILITADO');
    expect(menus.first['habilitado_en'], '2026-01-01 08:30:00');
    expect(menus.first['observacion'], 'Con sopa');
    // El menú histórico de otro tipo se conserva sin romperse.
    expect(menus.last['tipo'], 'DESAYUNO');
    // Los items siguen ligados al mismo menú después de reconstruir la tabla.
    final items = await db.query('menu_dia_items');
    expect(items.length, 1);
    expect(items.first['menu_dia_id'], menus.first['id']);
    // El CHECK nuevo rechaza el estado viejo.
    var rechazaViejo = false;
    try {
      await db.insert('menus_dia', {
        'fecha': '2026-01-02',
        'tipo': 'ALMUERZO',
        'estado': 'PUBLICADO',
        'usuario_id': 1,
        'creado_en': '2026-01-02 08:00:00',
      });
    } catch (_) {
      rechazaViejo = true;
    }
    expect(
      rechazaViejo,
      isTrue,
      reason: 'La base de datos debe rechazar el estado PUBLICADO.',
    );
  });

  test('un producto preparado sin receta se puede vender', () async {
    final auth = AuthRepository();
    final admin = (await auth.login('admin', '1234'))!;
    final catalog = CatalogRepository();
    final categoria = (await catalog.getCategorias()).first;
    final productoId = await catalog.saveProducto(
      Producto(
        nombre: 'Plato sin receta',
        categoriaId: categoria.id!,
        categoriaNombre: categoria.nombre,
        categoriaColor: categoria.color,
        precio: 10,
        tipo: 'PREPARADO',
        stockMinimo: 0,
        costoUnitario: 0,
        activo: true,
        stock: 0,
      ),
    );

    // El sistema no depende de que el producto tenga receta.
    expect(await catalog.motivoNoDisponible(productoId, 1), isNull);

    final menuRepo = MenuRepository();
    final menu = await menuRepo.crearMenu(DateTime.now(), 'ALMUERZO', admin.id);
    await menuRepo.agregarProducto(menu.id, productoId);
    await menuRepo.habilitar(menu.id);

    final cash = CashRepository();
    final caja = await cash.abrirCaja(
      fecha: DateTime.now(),
      fondoInicial: 100,
      usuarioId: admin.id,
    );

    final sales = SalesRepository();
    final pedidoId = await sales.crearPedido(
      usuarioId: admin.id,
      cajaId: caja.id,
      menuDiaId: menu.id,
      lineas: [
        CartLine(
          productoId: productoId,
          menuDiaItemId: (await menuRepo.getItems(menu.id)).first.id,
          nombre: 'Plato sin receta',
          precio: 10,
          cantidad: 1,
          tipo: 'PREPARADO',
        ),
      ],
      pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 10)],
    );
    final pedido = await sales.getPedido(pedidoId);
    expect(pedido.pedido.total, 10);
  });

  test('el menú se puede reabrir y acepta platos nuevos', () async {
    final auth = AuthRepository();
    final admin = (await auth.login('admin', '1234'))!;
    final catalog = CatalogRepository();
    final categoria = (await catalog.getCategorias()).first;
    Future<int> crearPlato(String nombre) => catalog.saveProducto(
      Producto(
        nombre: nombre,
        categoriaId: categoria.id!,
        categoriaNombre: categoria.nombre,
        categoriaColor: categoria.color,
        precio: 8,
        tipo: 'PREPARADO',
        stockMinimo: 0,
        costoUnitario: 0,
        activo: true,
        stock: 0,
      ),
    );
    final primero = await crearPlato('Plato de la mañana');
    final recordado = await crearPlato('Plato recordado');

    final menuRepo = MenuRepository();
    final menu = await menuRepo.crearMenu(DateTime.now(), 'ALMUERZO', admin.id);
    await menuRepo.agregarProducto(menu.id, primero);
    await menuRepo.habilitar(menu.id);

    final cash = CashRepository();
    final caja = await cash.abrirCaja(
      fecha: DateTime.now(),
      fondoInicial: 100,
      usuarioId: admin.id,
    );

    // Cerrar el menú no es definitivo: se puede reabrir cuando se quiera.
    await menuRepo.cerrar(menu.id);
    expect(
      (await menuRepo.getMenu(DateTime.now(), 'ALMUERZO'))!.cerrado,
      isTrue,
    );
    await menuRepo.habilitar(menu.id);
    expect(
      (await menuRepo.getMenu(DateTime.now(), 'ALMUERZO'))!.habilitado,
      isTrue,
    );

    // Un plato agregado después de habilitar queda en el menú...
    await menuRepo.agregarProducto(menu.id, recordado);
    final items = await menuRepo.getMenuHabilitado(DateTime.now(), 'ALMUERZO');
    expect(items.map((item) => item.productoId), contains(recordado));

    // ...y se puede vender sin problemas.
    final itemRecordado = items.firstWhere(
      (item) => item.productoId == recordado,
    );
    final sales = SalesRepository();
    final pedidoId = await sales.crearPedido(
      usuarioId: admin.id,
      cajaId: caja.id,
      menuDiaId: menu.id,
      lineas: [
        CartLine(
          productoId: recordado,
          menuDiaItemId: itemRecordado.id,
          nombre: 'Plato recordado',
          precio: 8,
          cantidad: 1,
          tipo: 'PREPARADO',
        ),
      ],
      pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 8)],
    );
    expect((await sales.getPedido(pedidoId)).pedido.total, 8);
  });

  test('el resumen muestra gasto en insumos y ganancia por producto', () async {
    final auth = AuthRepository();
    final admin = (await auth.login('admin', '1234'))!;
    final catalog = CatalogRepository();

    // Gasto en insumos: lo que entra al stock × costo del insumo.
    final unidad = (await catalog.getUnidades()).first;
    final insumoId = await catalog.saveInsumo(
      Insumo(
        nombre: 'Harina',
        unidadId: unidad.id,
        unidadAbreviatura: unidad.abreviatura,
        unidadNombre: unidad.nombre,
        unidadFamilia: unidad.familia,
        unidadFactorBase: unidad.factorBase,
        stockMinimo: 1,
        costoPromedio: 4,
        activo: true,
        stock: 0,
      ),
    );
    await catalog.ajustarStockInsumo(
      insumoId: insumoId,
      nuevoStock: 5,
      usuarioId: admin.id,
      motivo: 'Compra',
    );

    // Producto con costo unitario para la ganancia.
    final categoria = (await catalog.getCategorias()).first;
    final productoId = await catalog.saveProducto(
      Producto(
        nombre: 'Torta de prueba',
        categoriaId: categoria.id!,
        categoriaNombre: categoria.nombre,
        categoriaColor: categoria.color,
        precio: 10,
        tipo: 'PREPARADO',
        stockMinimo: 0,
        costoUnitario: 2,
        activo: true,
        stock: 0,
      ),
    );
    final menuRepo = MenuRepository();
    final menu = await menuRepo.crearMenu(DateTime.now(), 'ALMUERZO', admin.id);
    await menuRepo.agregarProducto(menu.id, productoId);
    await menuRepo.habilitar(menu.id);
    final cash = CashRepository();
    final caja = await cash.abrirCaja(
      fecha: DateTime.now(),
      fondoInicial: 50,
      usuarioId: admin.id,
    );
    final sales = SalesRepository();
    await sales.crearPedido(
      usuarioId: admin.id,
      cajaId: caja.id,
      menuDiaId: menu.id,
      lineas: [
        CartLine(
          productoId: productoId,
          menuDiaItemId: (await menuRepo.getItems(menu.id)).first.id,
          nombre: 'Torta de prueba',
          precio: 10,
          cantidad: 3,
          tipo: 'PREPARADO',
        ),
      ],
      pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 30)],
    );

    final reports = ReportRepository();
    final hoy = DateTime.now();
    final inicio = DateTime(hoy.year, hoy.month, hoy.day);
    final fin = inicio.add(const Duration(days: 1));
    final resumen = await reports.getResumen(inicio, fin);
    expect(resumen.ventas, 30);
    expect(resumen.gastoInsumos, 20); // 5 unidades × Bs 4
    expect(
      resumen.ganancia,
      resumen.ventas - resumen.gastoInsumos - resumen.salidas,
    );

    final productos = await reports.getProductos(inicio, fin);
    expect(productos.length, 1);
    expect(productos.first.costo, 6); // 3 unidades × Bs 2
    expect(productos.first.ganancia, 24); // Bs 30 de ventas − Bs 6 de costo
  });

  test('las categorías del almuerzo se migran a ALMUERZO COMPLETO', () async {
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    // Base vieja: ALMUERZO con las subcategorías PLATO SUELTO y COMPLETO.
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 10,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE usuarios (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nombre TEXT NOT NULL,
              usuario TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              rol TEXT NOT NULL CHECK (rol IN ('ADMIN','CAJERO')),
              perfil TEXT NOT NULL DEFAULT 'CAJERO',
              turno_asignado TEXT CHECK (turno_asignado IN ('MAÑANA','TARDE','AMBOS')),
              sueldo_base REAL NOT NULL DEFAULT 0,
              activo INTEGER NOT NULL DEFAULT 1,
              creado_en TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE categorias_producto (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nombre TEXT NOT NULL UNIQUE,
              color INTEGER NOT NULL DEFAULT 4280391418,
              siempre_disponible INTEGER NOT NULL DEFAULT 0,
              orden INTEGER NOT NULL DEFAULT 0,
              activo INTEGER NOT NULL DEFAULT 1,
              parent_id INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE productos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nombre TEXT NOT NULL UNIQUE,
              categoria_id INTEGER NOT NULL,
              descripcion TEXT,
              precio REAL NOT NULL DEFAULT 0,
              imagen BLOB,
              tipo TEXT NOT NULL CHECK (tipo IN ('DIRECTO','PREPARADO')),
              stock_minimo REAL NOT NULL DEFAULT 0,
              costo_unitario REAL NOT NULL DEFAULT 0,
              activo INTEGER NOT NULL DEFAULT 1,
              creado_en TEXT NOT NULL
            )
          ''');
          await db.insert('usuarios', {
            'nombre': 'Administrador',
            'usuario': 'admin',
            'password_hash': hashPassword('1234'),
            'rol': 'ADMIN',
            'turno_asignado': 'AMBOS',
            'sueldo_base': 0,
            'activo': 1,
            'creado_en': '2026-01-01 08:00:00',
          });
          await db.insert('categorias_producto', {
            'id': 1,
            'nombre': 'ALMUERZO',
            'color': 0xFF0F766E,
            'orden': 1,
          });
          await db.insert('categorias_producto', {
            'id': 2,
            'nombre': 'PLATO SUELTO',
            'color': 0xFF2563EB,
            'orden': 2,
            'parent_id': 1,
          });
          await db.insert('categorias_producto', {
            'id': 3,
            'nombre': 'COMPLETO',
            'color': 0xFFEA580C,
            'orden': 3,
            'parent_id': 1,
          });
          await db.insert('productos', {
            'nombre': 'Sopa vieja',
            'categoria_id': 2,
            'precio': 10,
            'tipo': 'PREPARADO',
            'creado_en': '2026-01-01 08:00:00',
          });
          await db.insert('productos', {
            'nombre': 'Completo viejo',
            'categoria_id': 3,
            'precio': 15,
            'tipo': 'PREPARADO',
            'creado_en': '2026-01-01 08:00:00',
          });
        },
      ),
    );
    await legacy.close();

    final db = await AppDatabase.instance.database;
    final categorias = await db.query('categorias_producto', orderBy: 'id');
    final nombres = categorias
        .map((categoria) => categoria['nombre']! as String)
        .toList();
    expect(
      nombres,
      containsAll([
        'PLATOS SUELTOS',
        'SOPAS',
        'BEBIDAS CALIENTES',
        'REFRESCOS',
        'FRAPPES',
      ]),
    );
    expect(nombres, isNot(contains('ALMUERZO')));
    expect(nombres, isNot(contains('PLATO SUELTO')));
    expect(nombres, isNot(contains('COMPLETO')));
    expect(
      categorias.every((categoria) => categoria['parent_id'] == null),
      isTrue,
    );

    // Los productos no se pierden: ambos pasan a PLATOS SUELTOS.
    final platosId =
        (await db.query(
              'categorias_producto',
              columns: ['id'],
              where: 'nombre = ?',
              whereArgs: ['PLATOS SUELTOS'],
            )).first['id']!
            as int;
    final productos = await db.query('productos', orderBy: 'id');
    expect(productos.length, 2);
    expect(
      productos.every((producto) => producto['categoria_id'] == platosId),
      isTrue,
    );
  });

  test('venta con receta e insumos insuficientes registra faltante', () async {
    final auth = AuthRepository();
    final admin = (await auth.login('admin', '1234'))!;
    final catalog = CatalogRepository();
    await catalog.saveCategoria(
      const CategoriaProducto(
        nombre: 'FALTANTES',
        color: 0xFF2563EB,
        siempreDisponible: false,
        orden: 1,
        activo: true,
      ),
    );
    final categoria = (await catalog.getCategorias()).firstWhere(
      (item) => item.nombre == 'FALTANTES',
    );
    final unidad = (await catalog.getUnidades()).firstWhere(
      (item) => item.abreviatura == 'und',
    );
    final insumoId = await catalog.saveInsumo(
      Insumo(
        nombre: 'Insumo faltante',
        unidadId: unidad.id,
        unidadAbreviatura: unidad.abreviatura,
        stockMinimo: 0,
        costoPromedio: 4,
        activo: true,
        stock: 0,
      ),
    );
    await catalog.ajustarStockInsumo(
      insumoId: insumoId,
      nuevoStock: 2,
      usuarioId: admin.id,
      motivo: 'Carga inicial',
    );
    final productoId = await catalog.saveProducto(
      Producto(
        nombre: 'Plato con receta',
        categoriaId: categoria.id!,
        categoriaNombre: categoria.nombre,
        categoriaColor: categoria.color,
        precio: 10,
        tipo: 'PREPARADO',
        stockMinimo: 0,
        costoUnitario: 0,
        activo: true,
        stock: 0,
      ),
    );
    await catalog.saveRecetaCantidades(productoId, {insumoId: 5});

    expect(await catalog.motivoNoDisponible(productoId, 1), isNull);
    expect(
      await catalog.advertenciaInsumos(productoId, 1),
      contains('Insumo faltante'),
    );

    final cash = CashRepository();
    final caja = await cash.abrirCaja(
      fecha: DateTime.now(),
      fondoInicial: 0,
      usuarioId: admin.id,
    );
    final sales = SalesRepository();
    final pedidoId = await sales.crearPedido(
      usuarioId: admin.id,
      cajaId: caja.id,
      referencia: 'Mesa faltante',
      lineas: [
        CartLine(
          productoId: productoId,
          nombre: 'Plato con receta',
          precio: 10,
          cantidad: 1,
          tipo: 'PREPARADO',
        ),
      ],
      pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 10)],
    );

    expect(await catalog.getStockInsumo(insumoId), 0);
    final db = await AppDatabase.instance.database;
    final consumos = await db.query('consumos_insumo');
    expect(consumos.length, 1);
    expect((consumos.first['cantidad'] as num).toDouble(), 2);

    final faltantes = await db.query('faltantes_insumo');
    expect(faltantes.length, 1);
    expect((faltantes.first['cantidad_requerida'] as num).toDouble(), 5);
    expect((faltantes.first['cantidad_disponible'] as num).toDouble(), 2);
    expect((faltantes.first['cantidad_consumida'] as num).toDouble(), 2);
    expect((faltantes.first['cantidad_faltante'] as num).toDouble(), 3);
    expect(faltantes.first['estado'], 'CONFIRMADO');

    final ahora = DateTime.now();
    final inicio = DateTime(ahora.year, ahora.month, ahora.day);
    final reporte = await ReportRepository().getFaltantes(
      inicio,
      inicio.add(const Duration(days: 1)),
    );
    expect(reporte.length, 1);
    expect(reporte.first.producto, 'Plato con receta');
    expect(reporte.first.insumo, 'Insumo faltante');
    expect(reporte.first.faltante, 3);

    await sales.anularPedido(pedidoId);
    expect(await catalog.getStockInsumo(insumoId), 2);
    final faltanteAnulado = await db.query('faltantes_insumo');
    expect(faltanteAnulado.first['estado'], 'ANULADO');
  });

  test('producto sin receta se vende sin consumos ni faltantes', () async {
    final auth = AuthRepository();
    final admin = (await auth.login('admin', '1234'))!;
    final catalog = CatalogRepository();
    await catalog.saveCategoria(
      const CategoriaProducto(
        nombre: 'SIN RECETA',
        color: 0xFF0F766E,
        siempreDisponible: false,
        orden: 1,
        activo: true,
      ),
    );
    final categoria = (await catalog.getCategorias()).firstWhere(
      (item) => item.nombre == 'SIN RECETA',
    );
    final productoId = await catalog.saveProducto(
      Producto(
        nombre: 'Producto independiente',
        categoriaId: categoria.id!,
        categoriaNombre: categoria.nombre,
        categoriaColor: categoria.color,
        precio: 8,
        tipo: 'PREPARADO',
        stockMinimo: 0,
        costoUnitario: 0,
        activo: true,
        stock: 0,
      ),
    );

    expect(await catalog.motivoNoDisponible(productoId, 1), isNull);
    expect(await catalog.advertenciaInsumos(productoId, 1), isNull);

    final cash = CashRepository();
    final caja = await cash.abrirCaja(
      fecha: DateTime.now(),
      fondoInicial: 0,
      usuarioId: admin.id,
    );
    final sales = SalesRepository();
    await sales.crearPedido(
      usuarioId: admin.id,
      cajaId: caja.id,
      lineas: [
        CartLine(
          productoId: productoId,
          nombre: 'Producto independiente',
          precio: 8,
          cantidad: 1,
          tipo: 'PREPARADO',
        ),
      ],
      pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 8)],
    );

    final db = await AppDatabase.instance.database;
    expect(await db.query('consumos_insumo'), isEmpty);
    expect(await db.query('faltantes_insumo'), isEmpty);
  });

  test('un almuerzo armado se vende y consume solo las recetas existentes', () async {
    final admin = (await AuthRepository().login('admin', '1234'))!;
    final catalog = CatalogRepository();
    final categorias = await catalog.getCategorias();
    final sopas = categorias.firstWhere(
      (categoria) => categoria.nombre == 'SOPAS',
    );
    final platos = categorias.firstWhere(
      (categoria) => categoria.nombre == 'PLATOS SUELTOS',
    );
    final unidad = (await catalog.getUnidades()).firstWhere(
      (item) => item.abreviatura == 'und',
    );
    final insumoId = await catalog.saveInsumo(
      Insumo(
        nombre: 'Insumo de sopa',
        unidadId: unidad.id,
        unidadAbreviatura: unidad.abreviatura,
        stockMinimo: 0,
        costoPromedio: 2,
        activo: true,
        stock: 0,
      ),
    );
    await catalog.ajustarStockInsumo(
      insumoId: insumoId,
      nuevoStock: 10,
      usuarioId: admin.id,
      motivo: 'Carga inicial',
    );

    Producto producto(String nombre, CategoriaProducto categoria, double precio) =>
        Producto(
          nombre: nombre,
          categoriaId: categoria.id!,
          categoriaNombre: categoria.nombre,
          categoriaColor: categoria.color,
          precio: precio,
          tipo: 'PREPARADO',
          stockMinimo: 0,
          costoUnitario: 0,
          activo: true,
          stock: 0,
        );

    final sopaId = await catalog.saveProducto(
      producto('Sopa del día', sopas, 8),
    );
    await catalog.saveRecetaCantidades(sopaId, {insumoId: 2});
    final segundoId = await catalog.saveProducto(
      producto('Segundo del día', platos, 12),
    );

    final comboId = await catalog.crearProductoCompuesto(
      nombre: 'Almuerzo armado',
      categoriaId: platos.id!,
      precio: 18,
      componenteIds: [sopaId, segundoId],
    );
    final combo = (await catalog.getProducto(comboId))!;
    expect(combo.esCompuesto, isTrue);
    expect((await catalog.getComponentes(comboId)).length, 2);

    final menuRepo = MenuRepository();
    final fecha = DateTime.now();
    final menu = await menuRepo.crearMenu(fecha, 'ALMUERZO', admin.id);
    await menuRepo.agregarCombo(
      menuDiaId: menu.id,
      productoId: comboId,
      nombre: 'Almuerzo armado',
      precio: 18,
    );
    await menuRepo.habilitar(menu.id);

    final combos = await menuRepo.getCombos(menu.id);
    expect(combos.length, 1);
    expect(combos.first.sumaComponentes, 20);

    final cash = CashRepository();
    final caja = await cash.abrirCaja(
      fecha: fecha,
      fondoInicial: 0,
      usuarioId: admin.id,
    );
    final venta = await SalesRepository().crearPedido(
      usuarioId: admin.id,
      cajaId: caja.id,
      menuDiaId: menu.id,
      lineas: [
        CartLine(
          productoId: comboId,
          menuDiaComboId: combos.first.id,
          nombre: 'Nombre enviado por el cliente',
          precio: 999,
          cantidad: 1,
        ),
      ],
      pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 18)],
    );

    final detalle = await SalesRepository().getPedido(venta);
    final principales = detalle.lineas.where((linea) => !linea.esComponente);
    final componentes = detalle.lineas.where((linea) => linea.esComponente);
    expect(detalle.pedido.total, 18);
    expect(principales.length, 1);
    expect(principales.first.nombre, 'Almuerzo armado');
    expect(componentes.length, 2);

    final db = await AppDatabase.instance.database;
    final consumos = await db.query('consumos_insumo');
    expect(consumos.length, 1);
    expect((consumos.first['cantidad'] as num).toDouble(), 2);

    final productos = await ReportRepository().getProductos(
      DateTime(fecha.year, fecha.month, fecha.day),
      DateTime(fecha.year, fecha.month, fecha.day + 1),
    );
    expect(productos.length, 1);
    expect(productos.first.nombre, 'Almuerzo armado');
    expect(productos.first.cantidad, 1);
    expect(productos.first.ventas, 18);

    final siguiente = await menuRepo.duplicarAnterior(
      fecha.add(const Duration(days: 1)),
      MenuRepository.tipoMenu,
      admin.id,
    );
    expect(siguiente, isNotNull);
    expect(siguiente!.habilitado, isTrue);
    expect((await menuRepo.getCombos(siguiente.id)).length, 1);
  });
}
