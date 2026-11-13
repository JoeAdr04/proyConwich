import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:test_code_02/core/auth_repository.dart';
import 'package:test_code_02/core/catalog_repository.dart';
import 'package:test_code_02/core/session.dart';
import 'package:test_code_02/data/database/app_database.dart';
import 'package:test_code_02/features/cash/presentation/cash_page.dart';
import 'package:test_code_02/features/dashboard/presentation/dashboard_page.dart';
import 'package:test_code_02/features/inventory/presentation/inventory_page.dart';
import 'package:test_code_02/features/menu/presentation/menu_page.dart';
import 'package:test_code_02/features/products/presentation/products_page.dart';
import 'package:test_code_02/features/reports/presentation/reports_page.dart';
import 'package:test_code_02/features/sales/presentation/sales_page.dart';
import 'package:test_code_02/features/users/presentation/users_page.dart';

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
    final unidades = await catalog.getUnidades();
    final unidad = unidades.first;
    await catalog.saveInsumo(
      Insumo(
        nombre: 'Papa',
        unidadId: unidad.id,
        unidadAbreviatura: unidad.abreviatura,
        unidadNombre: unidad.nombre,
        unidadFamilia: unidad.familia,
        unidadFactorBase: unidad.factorBase,
        stockMinimo: 2,
        costoPromedio: 3,
        activo: true,
        stock: 10,
      ),
    );
    await catalog.saveProducto(
      Producto(
        nombre: 'Almuerzo del día',
        categoriaId: categoria.id!,
        categoriaNombre: categoria.nombre,
        categoriaColor: categoria.color,
        precio: 15,
        tipo: 'PREPARADO',
        stockMinimo: 0,
        costoUnitario: 0,
        activo: true,
        stock: 0,
      ),
    );
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    final path = join(await getDatabasesPath(), 'sazon_restaurante_v2.db');
    await databaseFactory.deleteDatabase(path);
  });

  /// Deja correr las consultas reales de la base (sqflite ffi) y luego pinta.
  Future<void> verificarPantalla(
    WidgetTester tester,
    String nombre,
    Widget page,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: page)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      final error = tester.takeException();
      expect(
        error,
        isNull,
        reason: 'La pantalla $nombre desbordó en un teléfono angosto: $error',
      );
      if (error != null) return;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: 'La pantalla $nombre dejó un error de layout al desmontarse.',
    );
  }

  testWidgets(
    'el filtro de categoría padre incluye sus productos y subcategorías',
    (tester) async {
      final catalog = CatalogRepository();
      await tester.runAsync(
        () => catalog.saveCategoria(
          const CategoriaProducto(
            nombre: 'PADRE PRUEBA',
            color: 0xFF2563EB,
            siempreDisponible: false,
            orden: 10,
            activo: true,
          ),
        ),
      );
      final categorias = await tester.runAsync(catalog.getCategorias);
      final padre = categorias!.firstWhere(
        (categoria) => categoria.nombre == 'PADRE PRUEBA',
      );
      for (final nombre in ['HIJA UNO', 'HIJA DOS']) {
        await tester.runAsync(
          () => catalog.saveCategoria(
            CategoriaProducto(
              nombre: nombre,
              color: 0xFF2563EB,
              siempreDisponible: false,
              orden: 11,
              activo: true,
              parentId: padre.id,
            ),
          ),
        );
      }
      final categoriasConHijas = await tester.runAsync(catalog.getCategorias);
      final hijaUno = categoriasConHijas!.firstWhere(
        (categoria) => categoria.nombre == 'HIJA UNO',
      );
      final hijaDos = categoriasConHijas.firstWhere(
        (categoria) => categoria.nombre == 'HIJA DOS',
      );

      Future<void> crearProducto(String nombre, CategoriaProducto categoria) =>
          catalog.saveProducto(
            Producto(
              nombre: nombre,
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
      await tester.runAsync(() => crearProducto('Plato padre', padre));
      await tester.runAsync(() => crearProducto('Plato hija uno', hijaUno));
      await tester.runAsync(() => crearProducto('Plato hija dos', hijaDos));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductsPage(usuario: admin, refreshToken: 0)),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }

      final filtro = tester.widget<DropdownButtonFormField<int?>>(
        find.byType(DropdownButtonFormField<int?>),
      );
      filtro.onChanged!(padre.id);
      await tester.pump();
      expect(find.text('Plato padre'), findsOneWidget);
      expect(find.text('Plato hija uno'), findsOneWidget);
      expect(find.text('Plato hija dos'), findsOneWidget);
      expect(find.text('Almuerzo del día'), findsNothing);

      final filtroSubcategoria = tester.widget<DropdownButtonFormField<int?>>(
        find.byType(DropdownButtonFormField<int?>),
      );
      filtroSubcategoria.onChanged!(hijaUno.id);
      await tester.pump();
      expect(find.text('Plato hija uno'), findsOneWidget);
      expect(find.text('Plato padre'), findsNothing);
      expect(find.text('Plato hija dos'), findsNothing);
    },
  );

  testWidgets('pantallas operativas no desbordan en 360x640', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await verificarPantalla(
      tester,
      'Tablero',
      DashboardPage(usuario: admin, refreshToken: 0),
    );
    await verificarPantalla(
      tester,
      'Ventas',
      SalesPage(usuario: admin, refreshToken: 0),
    );
    await verificarPantalla(
      tester,
      'Caja',
      CashPage(usuario: admin, refreshToken: 0),
    );
    await verificarPantalla(
      tester,
      'Menú',
      MenuPage(usuario: admin, refreshToken: 0),
    );
  });

  testWidgets('catálogos y reportes no desbordan en 360x640', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await verificarPantalla(
      tester,
      'Productos',
      ProductsPage(usuario: admin, refreshToken: 0),
    );
    await verificarPantalla(
      tester,
      'Insumos',
      InventoryPage(usuario: admin, refreshToken: 0),
    );
    await verificarPantalla(
      tester,
      'Usuarios',
      UsersPage(usuario: admin, refreshToken: 0),
    );
    await verificarPantalla(
      tester,
      'Reportes',
      const ReportsPage(refreshToken: 0),
    );
  });

  testWidgets('los diálogos de alta abren y guardan en móvil', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> asentar() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    }

    final repository = CatalogRepository();

    // Producto.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductsPage(usuario: admin, refreshToken: 0),
        ),
      ),
    );
    await asentar();
    await tester.tap(find.text('Nuevo producto').first);
    await asentar();
    expect(find.widgetWithText(FilledButton, 'Guardar'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).first,
      'Producto móvil',
    );
    await tester.pump();
    // La categoría ya no viene por defecto: hay que elegirla.
    final categorias = await tester.runAsync(repository.getCategorias);
    final categoria = categorias!.firstWhere(
      (item) => item.nombre == 'ALMUERZOS',
    );
    final dropdown = tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    dropdown.onChanged!(categoria.id);
    final campo = tester.state<FormFieldState<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    campo.didChange(categoria.id);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await asentar();
    final productos = await tester.runAsync(repository.getProductos);
    expect(
      productos!.any((producto) => producto.nombre == 'Producto móvil'),
      isTrue,
    );

    // Receta (producto sembrado con id 1).
    await tester.tap(find.widgetWithText(OutlinedButton, 'Receta').first);
    await asentar();
    expect(find.byType(Checkbox), findsWidgets);
    await tester.tap(find.byType(Checkbox).first);
    await asentar();
    await tester.enterText(find.byType(TextFormField).last, '1/4');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar receta'));
    await asentar();
    final receta = await tester.runAsync(() => repository.getReceta(1));
    expect(receta!.length, 1);
    expect(receta.first.cantidad, 0.25);

    // Insumo.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryPage(usuario: admin, refreshToken: 0),
        ),
      ),
    );
    await asentar();
    await tester.tap(find.text('Nuevo insumo').first);
    await asentar();
    expect(find.widgetWithText(FilledButton, 'Guardar'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).first,
      'Insumo móvil',
    );
    await tester.enterText(find.byType(TextFormField).at(1), '2');
    await tester.enterText(find.byType(TextFormField).at(2), '5');
    await tester.pump();
    expect(find.textContaining('quedará en alerta'), findsOneWidget);

    await tester.ensureVisible(
      find.widgetWithText(
        SwitchListTile,
        'Disponible para venta directa',
      ),
    );
    await tester.tap(
      find.widgetWithText(
        SwitchListTile,
        'Disponible para venta directa',
      ),
    );
    await asentar();
    expect(
      find.text('Elegir imagen').evaluate().isNotEmpty ||
          find.text('Buscar imagen').evaluate().isNotEmpty,
      isTrue,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Nueva'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byType(TextFormField).last);
    await tester.enterText(find.byType(TextFormField).last, '7');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await asentar();
    final insumos = await tester.runAsync(repository.getInsumos);
    final insumo = insumos!.firstWhere(
      (insumo) => insumo.nombre == 'Insumo móvil',
    );
    expect(insumo.productoId, isNotNull);
    final producto = await tester.runAsync(
      () => repository.getProducto(insumo.productoId!),
    );
    expect(producto!.precio, 7);
  });
}
