import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:test_code_02/core/auth_repository.dart';
import 'package:test_code_02/core/cash_repository.dart';
import 'package:test_code_02/core/catalog_repository.dart';
import 'package:test_code_02/core/menu_repository.dart';
import 'package:test_code_02/core/report_repository.dart';
import 'package:test_code_02/core/sales_repository.dart';
import 'package:test_code_02/core/session.dart';
import 'package:test_code_02/data/database/app_database.dart';
import 'package:test_code_02/features/menu/presentation/menu_page.dart';
import 'package:test_code_02/features/reports/presentation/reports_page.dart';
import 'package:test_code_02/features/sales/presentation/sales_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Usuario admin;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    await databaseFactory.deleteDatabase(path);
    admin = (await AuthRepository().login('admin', '1234'))!;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    await databaseFactory.deleteDatabase(path);
  });

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  /// Espera a que el menú tenga la cantidad de items indicada, sin depender de
  /// tiempos fijos: los toques guardan en la base antes de actualizar la vista.
  Future<void> esperarItems(
    WidgetTester tester,
    int menuId,
    int cantidad,
  ) async {
    final menuRepository = MenuRepository();
    for (var i = 0; i < 40; i++) {
      final items = await tester.runAsync(
        () => menuRepository.getItems(menuId),
      );
      if ((items ?? const []).length == cantidad) {
        await tester.pump();
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  Future<(CatalogoPrueba, int)> sembrarCatalogo() async {
    final catalog = CatalogRepository();
    final categoria = (await catalog.getCategorias()).firstWhere(
      (item) => item.nombre == 'PLATOS SUELTOS',
    );
    final uno = await catalog.saveProducto(
      Producto(
        nombre: 'Plato uno',
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
    final dos = await catalog.saveProducto(
      Producto(
        nombre: 'Bebida dos',
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
    final caja = await CashRepository().abrirCaja(
      fecha: DateTime.now(),
      fondoInicial: 0,
      usuarioId: admin.id,
    );
    return ((uno, dos), caja.id);
  }

  testWidgets('Ventas oculta los productos fuera del menú y los despliega', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalogo = (await tester.runAsync(sembrarCatalogo))!;
    final ((platoUno, _), _) = catalogo;
    final menuRepository = MenuRepository();
    await tester.runAsync(() async {
      final menu = await menuRepository.crearMenu(
        DateTime.now(),
        MenuRepository.tipoMenu,
        admin.id,
      );
      await menuRepository.agregarProducto(menu.id, platoUno);
      await menuRepository.habilitar(menu.id);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SalesPage(usuario: admin, refreshToken: 0)),
      ),
    );
    await asentar(tester);

    expect(find.text('Plato uno'), findsWidgets);
    expect(find.text('Bebida dos'), findsNothing);
    expect(find.text('Productos agotados o fuera del menú'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(
      find.text('Productos agotados o fuera del menú'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Productos agotados o fuera del menú'));
    await tester.pumpAndSettle();
    expect(find.text('Bebida dos'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ventas fija Pedido al 25% derecho en escritorio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalogo = (await tester.runAsync(sembrarCatalogo))!;
    final ((platoId, _), _) = catalogo;
    final catalog = CatalogRepository();
    final categoria = (await tester.runAsync(() => catalog.getCategorias()))!
        .firstWhere((item) => item.nombre == 'PLATOS SUELTOS');
    final menuRepository = MenuRepository();
    await tester.runAsync(() async {
      final menu = await menuRepository.crearMenu(
        DateTime.now(),
        MenuRepository.tipoMenu,
        admin.id,
      );
      await menuRepository.agregarProducto(menu.id, platoId);
      for (var index = 0; index < 10; index++) {
        final productoId = await catalog.saveProducto(
          Producto(
            nombre: 'Plato largo $index',
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
        await menuRepository.agregarProducto(menu.id, productoId);
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SalesPage(usuario: admin, refreshToken: 0)),
      ),
    );
    await asentar(tester);

    final pedido = find.text('Pedido');
    for (var index = 0; index < 60 && pedido.evaluate().isEmpty; index++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(pedido, findsOneWidget);
    final producto = find.text('Plato uno').first;
    final posicionPedido = tester.getTopLeft(pedido);
    expect(posicionPedido.dx, greaterThan(tester.getTopLeft(producto).dx));
    final panelScroll = find
        .ancestor(of: pedido, matching: find.byType(SingleChildScrollView))
        .first;
    expect(tester.getSize(panelScroll).width, closeTo(300, 0.1));

    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(pedido).dy, closeTo(posicionPedido.dy, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ventas pregunta por la nota tras un pago mixto', (tester) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalogo = (await tester.runAsync(sembrarCatalogo))!;
    final ((platoId, _), _) = catalogo;
    final menuRepository = MenuRepository();
    await tester.runAsync(() async {
      final menu = await menuRepository.crearMenu(
        DateTime.now(),
        MenuRepository.tipoMenu,
        admin.id,
      );
      await menuRepository.agregarProducto(menu.id, platoId);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SalesPage(usuario: admin, refreshToken: 0)),
      ),
    );
    await asentar(tester);
    expect(tester.takeException(), isNull, reason: 'al cargar Ventas');
    await tester.tap(find.text('Plato uno').first);
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'al agregar un producto');
    await tester.ensureVisible(find.text('Pagado'));
    await tester.tap(find.text('Pagado'));
    await tester.pumpAndSettle();
    final cobroError = tester.takeException();
    expect(cobroError, isNull, reason: 'al abrir el cobro');

    final camposPago = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(camposPago, findsNWidgets(2));
    await tester.enterText(camposPago.first, '7');
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'al editar el efectivo');
    expect(tester.widget<TextField>(camposPago.last).controller?.text, '3.00');
    await tester.tap(find.text('Confirmar pago'));
    await asentar(tester);
    expect(tester.takeException(), isNull, reason: 'al registrar el pago');

    final hoy = DateTime.now();
    final inicio = DateTime(hoy.year, hoy.month, hoy.day);
    final reportes = await tester.runAsync(
      () => ReportRepository().getPedidos(
        inicio,
        inicio.add(const Duration(days: 1)),
      ),
    );
    expect(reportes, hasLength(1));
    expect(reportes!.single.total, 10);
    expect(reportes.single.efectivo, 7);
    expect(reportes.single.qr, 3);
    expect(find.text('Fichas del pedido'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ventas agrega el completo al precio automático con un toque', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalogo = (await tester.runAsync(sembrarCatalogo))!;
    final ((platoId, _), _) = catalogo;
    final catalog = CatalogRepository();
    final categorias = (await tester.runAsync(catalog.getCategorias))!;
    final sopas = categorias.firstWhere((item) => item.nombre == 'SOPAS');
    final sopaId = await tester.runAsync(
      () => catalog.saveProducto(
        Producto(
          nombre: 'Sopa de maní',
          categoriaId: sopas.id!,
          categoriaNombre: sopas.nombre,
          categoriaColor: sopas.color,
          precio: 4,
          tipo: 'PREPARADO',
          stockMinimo: 0,
          costoUnitario: 0,
          activo: true,
          stock: 0,
        ),
      ),
    );
    final menuRepository = MenuRepository();
    await tester.runAsync(() async {
      final menu = await menuRepository.crearMenu(
        DateTime.now(),
        MenuRepository.tipoMenu,
        admin.id,
      );
      await menuRepository.agregarProducto(menu.id, sopaId!);
      await menuRepository.agregarProducto(menu.id, platoId);
      await menuRepository.habilitar(menu.id);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SalesPage(usuario: admin, refreshToken: 0)),
      ),
    );
    await asentar(tester);

    final completo = find.text('Completo · Bs 14.00');
    await tester.ensureVisible(completo);
    expect(completo, findsOneWidget);
    await tester.tap(completo);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Incluye Sopa de maní · Bs 4.00'));
    expect(find.text('Plato uno completo'), findsOneWidget);
    expect(find.text('Incluye Sopa de maní · Bs 4.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Menú selecciona toda una categoría con un checkbox binario', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(sembrarCatalogo);
    final catalog = CatalogRepository();
    final categorias = (await tester.runAsync(catalog.getCategorias))!;
    final sopa = categorias.firstWhere((item) => item.nombre == 'SOPAS');
    await tester.runAsync(
      () => catalog.saveProducto(
        Producto(
          nombre: 'Sopa de maní',
          categoriaId: sopa.id!,
          categoriaNombre: sopa.nombre,
          categoriaColor: sopa.color,
          precio: 4,
          tipo: 'PREPARADO',
          stockMinimo: 0,
          costoUnitario: 0,
          activo: true,
          stock: 0,
        ),
      ),
    );
    final menuRepository = MenuRepository();
    final menuId = (await tester.runAsync(() async {
      final menu = await menuRepository.crearMenu(
        DateTime.now(),
        MenuRepository.tipoMenu,
        admin.id,
      );
      return menu.id;
    }))!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MenuPage(usuario: admin, refreshToken: 0)),
      ),
    );
    await asentar(tester);

    final categoriaPlatos = categorias.firstWhere(
      (item) => item.nombre == 'PLATOS SUELTOS',
    );
    final checkbox = find.byKey(
      ValueKey('seleccionar-categoria-${categoriaPlatos.id}'),
    );
    await tester.ensureVisible(checkbox);
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    await tester.tap(checkbox);
    // El toque guarda al instante en la base: ya no hay botón "Listo".
    await esperarItems(tester, menuId, 2);
    await asentar(tester);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    final items = (await tester.runAsync(
      () => menuRepository.getItems(menuId),
    ))!;
    expect(items.every((item) => !item.esSopa), isTrue);
    expect(
      find.byKey(ValueKey('seleccionar-categoria-${sopa.id}')),
      findsNothing,
    );

    // Desmarcar la categoría: también se guarda al instante.
    await tester.ensureVisible(checkbox);
    await tester.pump();
    await tester.tap(checkbox);
    await esperarItems(tester, menuId, 0);
    await asentar(tester);
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Menú muestra todas las categorías y habilita en Ventas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(sembrarCatalogo);
    final catalog = CatalogRepository();
    await tester.runAsync(
      () => catalog.saveCategoria(
        const CategoriaProducto(
          nombre: 'POSTRES',
          color: 0xFFCA8A04,
          siempreDisponible: false,
          orden: 7,
          activo: true,
        ),
      ),
    );
    final categorias = (await tester.runAsync(catalog.getCategorias))!;
    const nombresCategorias = ['REFRESCOS', 'COMBOS', 'POSTRES'];
    final productos = <String, int>{};
    for (final nombreCategoria in nombresCategorias) {
      final categoria = categorias.firstWhere(
        (item) => item.nombre == nombreCategoria,
      );
      final productoId = (await tester.runAsync(
        () => catalog.saveProducto(
          Producto(
            nombre: 'Producto $nombreCategoria',
            categoriaId: categoria.id!,
            categoriaNombre: categoria.nombre,
            categoriaColor: categoria.color,
            precio: 5,
            tipo: 'PREPARADO',
            stockMinimo: 0,
            costoUnitario: 0,
            activo: true,
            stock: 0,
          ),
        ),
      ))!;
      productos[nombreCategoria] = productoId;
    }
    final menuRepository = MenuRepository();
    final menuId = (await tester.runAsync(() async {
      final menu = await menuRepository.crearMenu(
        DateTime.now(),
        MenuRepository.tipoMenu,
        admin.id,
      );
      return menu.id;
    }))!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MenuPage(usuario: admin, refreshToken: 0)),
      ),
    );
    await asentar(tester);

    for (var index = 0; index < nombresCategorias.length; index++) {
      final nombre = 'Producto ${nombresCategorias[index]}';
      final producto = find.text(nombre);
      expect(producto, findsOneWidget);
      await tester.ensureVisible(producto);
      await tester.tap(producto);
      await esperarItems(tester, menuId, index + 1);
      await asentar(tester);
    }
    expect(
      (await tester.runAsync(
        () => menuRepository.getMenuHabilitado(
          DateTime.now(),
          MenuRepository.tipoMenu,
        ),
      ))!.map((item) => item.productoId).toSet(),
      containsAll(productos.values),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SalesPage(usuario: admin, refreshToken: 0)),
      ),
    );
    await asentar(tester);
    for (final nombreCategoria in nombresCategorias) {
      expect(find.text('Producto $nombreCategoria'), findsWidgets);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('el cajero ve solo sus pedidos y el detalle es de solo lectura', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalogo = (await tester.runAsync(sembrarCatalogo))!;
    final ((productoId, _), cajaId) = catalogo;
    final (cajero, pedidoPropioId) = (await tester.runAsync(() async {
      final auth = AuthRepository();
      await auth.saveUsuario(
        nombre: 'Cajero de prueba',
        usuario: 'cajero_historial',
        perfil: Perfil.cajero,
        activo: true,
        permisos: Perfil.vistasPorDefecto[Perfil.cajero]!,
        password: 'prueba123',
      );
      final usuario = (await auth.login('cajero_historial', 'prueba123'))!;
      final pedidoPropio = await SalesRepository().crearPedido(
        usuarioId: usuario.id,
        cajaId: cajaId,
        referencia: 'Mesa propia',
        lineas: [
          CartLine(
            productoId: productoId,
            nombre: 'Plato uno',
            precio: 10,
            cantidad: 1,
          ),
        ],
        pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 10)],
      );
      await SalesRepository().crearPedido(
        usuarioId: admin.id,
        cajaId: cajaId,
        referencia: 'Mesa de otra persona',
        lineas: [
          CartLine(
            productoId: productoId,
            nombre: 'Plato uno',
            precio: 10,
            cantidad: 1,
          ),
        ],
        pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 10)],
      );
      return (usuario, pedidoPropio);
    }))!;
    final detallePropio = (await tester.runAsync(
      () => SalesRepository().getPedido(pedidoPropioId),
    ))!;
    expect(
      detallePropio.lineas.singleWhere((linea) => !linea.esComponente).nombre,
      'Plato uno',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReportsPage(usuario: cajero, refreshToken: 0)),
      ),
    );
    await asentar(tester);

    expect(find.text('Mis pedidos'), findsOneWidget);
    expect(find.textContaining('Mesa propia'), findsOneWidget);
    expect(find.textContaining('Mesa de otra persona'), findsNothing);
    await tester.tap(find.textContaining('Mesa propia'));
    await asentar(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Plato uno'), findsOneWidget);
    expect(find.text('EFECTIVO · CONFIRMADO'), findsOneWidget);
    expect(find.text('Cobrar'), findsNothing);
    expect(find.text('Anular'), findsNothing);
    expect(find.text('Agregar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ventas abre el detalle con el ojo y permite cancelar/anular', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalogo = (await tester.runAsync(sembrarCatalogo))!;
    final ((platoId, _), cajaId) = catalogo;
    await tester.runAsync(
      () => SalesRepository().crearPedido(
        usuarioId: admin.id,
        cajaId: cajaId,
        lineas: [
          CartLine(
            productoId: platoId,
            nombre: 'Plato uno',
            precio: 10,
            cantidad: 1,
          ),
        ],
        pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 10)],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SalesPage(usuario: admin, refreshToken: 0)),
      ),
    );
    await asentar(tester);

    final pedido = find.text('#1');
    await tester.ensureVisible(pedido);
    final ojo = find.byTooltip('Ver detalle');
    await tester.ensureVisible(ojo);
    await tester.tap(ojo);
    await asentar(tester);
    expect(find.text('Pedido #1'), findsOneWidget);
    expect(find.textContaining('Plato uno'), findsWidgets);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('ANULAR'));
    await tester.tap(find.text('ANULAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('ANULAR'));
    await tester.pumpAndSettle();
    final motivo = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(motivo, 'Prueba de anulación');
    await tester.tap(find.text('Anular venta'));
    await asentar(tester);
    await tester.ensureVisible(find.text('ANULADA'));
    expect(find.text('ANULADA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reportes muestra los gráficos de ingresos y de cantidades', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final catalogo = (await tester.runAsync(sembrarCatalogo))!;
    final ((platoUno, bebidaDos), cajaId) = catalogo;
    await tester.runAsync(
      () => SalesRepository().crearPedido(
        usuarioId: admin.id,
        cajaId: cajaId,
        lineas: [
          CartLine(
            productoId: platoUno,
            nombre: 'Plato uno',
            precio: 10,
            cantidad: 3,
          ),
          CartLine(
            productoId: bebidaDos,
            nombre: 'Bebida dos',
            precio: 10,
            cantidad: 6,
          ),
        ],
        pagos: const [PagoInput(metodo: 'EFECTIVO', monto: 90)],
      ),
    );
    await tester.runAsync(
      () => CashRepository().registrarSalida(
        cajaId: cajaId,
        usuarioId: admin.id,
        monto: 15,
        descripcion: 'Salida de emergencia',
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ReportsPage(refreshToken: 0))),
    );
    await asentar(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('VENTAS NETAS'), findsOneWidget);
    expect(find.text('Bs 75.00'), findsOneWidget);
    expect(find.text('Salidas de emergencia'), findsOneWidget);
    expect(find.text('Cobros en efectivo'), findsNothing);
    expect(find.text('Cobros QR'), findsNothing);

    await tester.tap(find.text('Productos'));
    await tester.pumpAndSettle();

    expect(find.text('Ingresos por producto'), findsOneWidget);
    expect(find.text('Productos más vendidos'), findsOneWidget);
    expect(find.text('Bebida dos'), findsWidgets);
    final tablaProductos = tester.widget<DataTable>(
      find.byType(DataTable).first,
    );
    expect((tablaProductos.rows.last.cells.first.child as Text).data, 'TOTAL');
    expect((tablaProductos.rows.last.cells[3].child as Text).data, 'Bs 90.00');
    expect(tester.takeException(), isNull);
  });
}

typedef CatalogoPrueba = (int platoUno, int bebidaDos);
