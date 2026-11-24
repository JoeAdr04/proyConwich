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
import 'package:test_code_02/ui/categoria_editor.dart';

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
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
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
    'el filtro de categoría muestra solo los productos de esa categoría',
    (tester) async {
      final catalog = CatalogRepository();
      for (final nombre in ['CATEGORIA A', 'CATEGORIA B']) {
        await tester.runAsync(
          () => catalog.saveCategoria(
            CategoriaProducto(
              nombre: nombre,
              color: 0xFF2563EB,
              siempreDisponible: false,
              orden: 10,
              activo: true,
            ),
          ),
        );
      }
      final categorias = await tester.runAsync(catalog.getCategorias);
      final categoriaA = categorias!.firstWhere(
        (categoria) => categoria.nombre == 'CATEGORIA A',
      );
      final categoriaB = categorias.firstWhere(
        (categoria) => categoria.nombre == 'CATEGORIA B',
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
      await tester.runAsync(() => crearProducto('Plato A', categoriaA));
      await tester.runAsync(() => crearProducto('Plato B', categoriaB));

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

      // El menú se ancla al campo y muestra acciones junto a cada categoría;
      // el formulario de edición solo se abre al tocar el lápiz.
      await tester.tap(find.byType(CategoriaPickerField));
      await tester.pumpAndSettle();
      expect(find.text('Categorías'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Nueva categoría'), findsNothing);
      final filaA = find.widgetWithText(ListTile, 'CATEGORIA A');
      expect(
        find.descendant(
          of: filaA,
          matching: find.byIcon(Icons.edit_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: filaA,
          matching: find.byIcon(Icons.delete_outline),
        ),
        findsOneWidget,
      );
      final filaSistema = find.widgetWithText(ListTile, 'REFRESCOS');
      final papeleraSistema = find.descendant(
        of: filaSistema,
        matching: find.byIcon(Icons.delete_outline),
      );
      expect(papeleraSistema, findsOneWidget);
      final botonPapeleraSistema = find.ancestor(
        of: papeleraSistema,
        matching: find.byType(IconButton),
      );
      expect(
        tester.widget<IconButton>(botonPapeleraSistema).onPressed,
        isNull,
      );
      final editar = find.descendant(
        of: filaA,
        matching: find.byTooltip('Editar'),
      );
      await tester.ensureVisible(editar);
      await tester.pump();
      await tester.tap(editar);
      await tester.pumpAndSettle();
      expect(find.text('Editar categoría'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(filaA);
      await tester.pump();
      await tester.tap(filaA);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(find.text('Plato A'), findsOneWidget);
      expect(find.text('Plato B'), findsNothing);
      expect(find.text('Almuerzo del día'), findsNothing);

      await tester.tap(find.byType(CategoriaPickerField));
      await tester.pumpAndSettle();
      final filaB = find.widgetWithText(ListTile, 'CATEGORIA B');
      await tester.ensureVisible(filaB);
      await tester.pump();
      await tester.tap(filaB);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(find.text('Plato B'), findsOneWidget);
      expect(find.text('Plato A'), findsNothing);
    },
  );

  testWidgets(
    'Nuevo combo permite buscar y filtrar productos por categoría',
    (tester) async {
      final catalog = CatalogRepository();
      final categorias = await tester.runAsync(catalog.getCategorias);
      final categoriaRefrescos = categorias!.firstWhere(
        (categoria) => categoria.nombre == 'REFRESCOS',
      );
      final productosIniciales = await tester.runAsync(catalog.getProductos);
      final categoriaInicial = productosIniciales!.first.categoriaNombre;
      await tester.runAsync(
        () => catalog.saveProducto(
          Producto(
            nombre: 'Bebida destacada',
            categoriaId: categoriaRefrescos.id!,
            categoriaNombre: categoriaRefrescos.nombre,
            categoriaColor: categoriaRefrescos.color,
            precio: 8,
            tipo: 'PREPARADO',
            stockMinimo: 0,
            costoUnitario: 0,
            activo: true,
            stock: 0,
          ),
        ),
      );

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
      await tester.tap(find.widgetWithText(OutlinedButton, 'Nuevo combo'));
      await tester.pumpAndSettle();

      // El diálogo comparte el label 'Buscar producto' con el buscador de la
      // página, así que se acota el finder al AlertDialog para no ambiguar.
      final buscador = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Buscar producto',
        ),
      );
      await tester.enterText(buscador, 'Bebida');
      await tester.pump();
      expect(
        find.widgetWithText(CheckboxListTile, 'Bebida destacada'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(CheckboxListTile, 'Almuerzo del día'),
        findsNothing,
      );

      await tester.enterText(buscador, '');
      await tester.pump();
      final chipCategoria = find.widgetWithText(ChoiceChip, categoriaInicial);
      await tester.ensureVisible(chipCategoria);
      await tester.tap(chipCategoria);
      await tester.pump();
      expect(
        find.widgetWithText(CheckboxListTile, 'Almuerzo del día'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(CheckboxListTile, 'Bebida destacada'),
        findsNothing,
      );
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

    /// Espera a que aparezca un widget sin depender de tiempos fijos: los
    /// diálogos se abren tras consultas a la BD que pueden tardar más.
    Future<void> esperar(Finder finder) async {
      for (var i = 0; i < 40; i++) {
        if (finder.evaluate().isNotEmpty) {
          await tester.pump();
          return;
        }
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
        home: Scaffold(body: ProductsPage(usuario: admin, refreshToken: 0)),
      ),
    );
    await asentar();
    await tester.tap(find.text('Nuevo producto').first);
    await asentar();
    expect(find.widgetWithText(FilledButton, 'Guardar'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Producto móvil');
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
    await tester.enterText(find.byType(TextFormField).at(2), '1');
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
        home: Scaffold(body: InventoryPage(usuario: admin, refreshToken: 0)),
      ),
    );
    await asentar();
    await tester.tap(find.text('Registrar compra'));
    await esperar(find.widgetWithText(FilledButton, 'Registrar'));
    expect(find.widgetWithText(FilledButton, 'Registrar'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Insumo móvil');
    await tester.enterText(find.byType(TextFormField).at(1), '2');
    await tester.enterText(find.byType(TextFormField).at(2), '5');
    await tester.pump();

    await tester.ensureVisible(
      find.widgetWithText(SwitchListTile, '¿Lo vendes directo?'),
    );
    await tester.tap(
      find.widgetWithText(SwitchListTile, '¿Lo vendes directo?'),
    );
    await asentar();
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar'));
    await esperar(find.widgetWithText(FilledButton, 'Crear producto'));
    // Se abre el diálogo de creación de producto.
    expect(find.widgetWithText(FilledButton, 'Crear producto'), findsOneWidget);
    final categoriasProd = await tester.runAsync(repository.getCategorias);
    final categoriaProd = categoriasProd!.firstWhere(
      (item) => item.nombre == 'ALMUERZOS',
    );
    final dropdownProd = tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    dropdownProd.onChanged!(categoriaProd.id);
    final campoProd = tester.state<FormFieldState<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    campoProd.didChange(categoriaProd.id);
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).first, '7');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Crear producto'));
    // El guardado escribe en la BD antes de vincular el producto; se espera a
    // que el vínculo exista en vez de confiar en un tiempo fijo.
    Insumo? insumo;
    for (var i = 0; i < 40 && insumo?.productoId == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final insumos = await tester.runAsync(repository.getInsumos);
      insumo = insumos
          ?.where((insumo) => insumo.nombre == 'Insumo móvil')
          .firstOrNull;
    }
    expect(insumo, isNotNull);
    expect(insumo!.productoId, isNotNull);
    final producto = await tester.runAsync(
      () => repository.getProducto(insumo!.productoId!),
    );
    expect(producto!.precio, 7);
  });
}
