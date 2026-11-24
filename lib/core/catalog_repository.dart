import 'dart:typed_data';

import '../data/database/app_database.dart';
import 'date_utils.dart';

class CategoriaProducto {
  const CategoriaProducto({
    this.id,
    required this.nombre,
    required this.color,
    required this.siempreDisponible,
    required this.orden,
    required this.activo,
    this.parentId,
    this.parentNombre,
  });

  final int? id;
  final String nombre;
  final int color;
  final bool siempreDisponible;
  final int orden;
  final bool activo;
  final int? parentId;
  final String? parentNombre;

  bool get esSubcategoria => parentId != null;

  String get nombreCompleto =>
      parentNombre == null ? nombre : '$parentNombre · $nombre';
}

class UnidadMedida {
  const UnidadMedida({
    required this.id,
    required this.nombre,
    required this.abreviatura,
    this.familia = 'OTRO',
    this.factorBase = 1,
  });

  final int id;
  final String nombre;
  final String abreviatura;

  /// `MASA`, `VOLUMEN`, `UNIDAD`, `PORCION` u `OTRO`.
  final String familia;

  /// Cuántas unidades base (g, ml o 1) contiene una unidad de este tipo.
  final double factorBase;

  bool get esConvertible => familia == 'MASA' || familia == 'VOLUMEN';
}

class Producto {
  const Producto({
    this.id,
    required this.nombre,
    required this.categoriaId,
    required this.categoriaNombre,
    required this.categoriaColor,
    this.categoriaParentId,
    this.categoriaParentNombre,
    this.descripcion,
    required this.precio,
    this.imagen,
    required this.tipo,
    required this.stockMinimo,
    required this.costoUnitario,
    required this.activo,
    required this.stock,
    this.agotado = false,
    this.esCombo = false,
    this.categoriaSiempreDisponible = false,
    this.insumoVinculadoId,
    this.esCompuesto = false,
  });

  final int? id;
  final String nombre;
  final int categoriaId;
  final String categoriaNombre;
  final int categoriaColor;
  final int? categoriaParentId;
  final String? categoriaParentNombre;
  final String? descripcion;
  final double precio;
  final Uint8List? imagen;
  final String tipo;
  final double stockMinimo;
  final double costoUnitario;
  final bool activo;
  final double stock;

  /// Marcado como agotado desde Ventas. Se oculta de la venta y se puede
  /// rehabilitar desde el Menú del día.
  final bool agotado;

  /// Combo armado desde Productos. No descuenta stock ni insumos.
  final bool esCombo;

  /// Si la categoría se vende siempre (sin depender del menú del día).
  final bool categoriaSiempreDisponible;

  /// Insumo del que se generó este producto de venta directa.
  final int? insumoVinculadoId;

  /// Producto compuesto (almuerzo completo o combo) armado desde el menú.
  final bool esCompuesto;

  bool get esDirecto => tipo == 'DIRECTO';
  bool get esVentaDirecta => insumoVinculadoId != null;

  String get categoriaEtiqueta => categoriaParentNombre == null
      ? categoriaNombre
      : '$categoriaParentNombre · $categoriaNombre';
}

class ProductoComponente {
  const ProductoComponente({
    required this.componenteId,
    required this.nombre,
    required this.precio,
    required this.categoriaNombre,
    required this.categoriaColor,
    this.cantidad = 1,
    this.orden = 0,
    this.imagen,
  });

  final int componenteId;
  final String nombre;
  final double precio;
  final String categoriaNombre;
  final int categoriaColor;
  final double cantidad;
  final int orden;
  final Uint8List? imagen;
}

class Insumo {
  const Insumo({
    this.id,
    required this.nombre,
    required this.unidadId,
    required this.unidadAbreviatura,
    required this.stockMinimo,
    required this.costoPromedio,
    required this.activo,
    required this.stock,
    this.unidadNombre = '',
    this.unidadFamilia = 'OTRO',
    this.unidadFactorBase = 1,
    this.ventaDirecta = false,
    this.precioVenta = 0,
    this.productoId,
    this.categoriaVentaDirectaId,
    this.imagen,
    this.consumible = true,
  });

  final int? id;
  final String nombre;
  final int unidadId;
  final String unidadAbreviatura;
  final String unidadNombre;
  final String unidadFamilia;
  final double unidadFactorBase;
  final double stockMinimo;
  final double costoPromedio;
  final bool activo;
  final double stock;

  /// Se vende tal cual desde Productos con una receta de una unidad.
  final bool ventaDirecta;
  final double precioVenta;
  final int? productoId;
  final int? categoriaVentaDirectaId;

  /// Imagen del producto generado (solo para venta directa).
  final Uint8List? imagen;

  /// `false` para insumos no consumibles (cucharas, platos, vasos): se
  /// controlan como inventario pero no se descuentan con recetas.
  final bool consumible;

  bool get bajoStock => stock <= stockMinimo;
  bool get unidadConvertible =>
      unidadFamilia == 'MASA' || unidadFamilia == 'VOLUMEN';
}

class RecetaLinea {
  const RecetaLinea({
    required this.insumoId,
    required this.insumoNombre,
    required this.unidadAbreviatura,
    required this.cantidad,
    required this.stock,
  });

  final int insumoId;
  final String insumoNombre;
  final String unidadAbreviatura;
  final double cantidad;
  final double stock;
}

/// Presentación/variante de un producto (por ejemplo, el tamaño de un
/// refresco). El stock vive en el producto base; cada presentación aporta su
/// propio precio e imagen.
class ProductoPresentacion {
  const ProductoPresentacion({
    this.id,
    required this.productoId,
    required this.nombre,
    required this.precio,
    required this.orden,
    required this.activo,
    this.imagen,
  });

  final int? id;
  final int productoId;
  final String nombre;
  final double precio;
  final int orden;
  final bool activo;
  final Uint8List? imagen;
}

class CatalogRepository {
  Future<List<CategoriaProducto>> getCategorias({
    bool soloActivas = false,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.*, p.nombre AS parent_nombre
      FROM categorias_producto c
      LEFT JOIN categorias_producto p ON p.id = c.parent_id
      ${soloActivas ? 'WHERE c.activo = 1' : ''}
      ORDER BY c.activo DESC, c.orden, c.nombre COLLATE NOCASE
    ''');
    return rows
        .map(
          (row) => CategoriaProducto(
            id: row['id']! as int,
            nombre: row['nombre']! as String,
            color: row['color']! as int,
            siempreDisponible: (row['siempre_disponible'] as num).toInt() == 1,
            orden: (row['orden'] as num?)?.toInt() ?? 0,
            activo: (row['activo'] as num).toInt() == 1,
            parentId: row['parent_id'] as int?,
            parentNombre: row['parent_nombre'] as String?,
          ),
        )
        .toList();
  }

  /// Guarda la categoría y devuelve su id (nuevo o existente).
  Future<int> saveCategoria(CategoriaProducto categoria) async {
    final db = await AppDatabase.instance.database;
    final values = <String, Object?>{
      'nombre': categoria.nombre.trim().toUpperCase(),
      'color': categoria.color,
      'parent_id': null,
      'siempre_disponible': categoria.siempreDisponible ? 1 : 0,
      'orden': categoria.orden,
      'activo': categoria.activo ? 1 : 0,
    };
    if (categoria.id == null) {
      return db.insert('categorias_producto', values);
    }
    await db.update(
      'categorias_producto',
      values,
      where: 'id = ?',
      whereArgs: [categoria.id],
    );
    return categoria.id!;
  }

  Future<void> setCategoriaActiva(int id, bool activo) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'categorias_producto',
      {'activo': activo ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Categorías que el sistema usa por nombre (sopa, completo, presentaciones,
  /// combos y venta directa). Renombrarlas o eliminarlas rompe esos flujos y la
  /// app las vuelve a sembrar al abrir la base, así que solo se les permite
  /// cambiar el color.
  static const _categoriasProtegidas = {
    'PLATOS SUELTOS',
    'SOPAS',
    'BEBIDAS CALIENTES',
    'REFRESCOS',
    'FRAPPES',
    'COMBOS',
    'VENTA DIRECTA',
  };

  static bool esCategoriaProtegida(String nombre) =>
      _categoriasProtegidas.contains(nombre.trim().toUpperCase());

  /// Cuántos productos (activos o no) usan la categoría.
  Future<int> countProductosCategoria(int categoriaId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM productos WHERE categoria_id = ?',
      [categoriaId],
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  /// Pasa todos los productos de una categoría a otra (antes de eliminarla).
  Future<void> moverProductosCategoria({
    required int desdeId,
    required int hastaId,
  }) async {
    if (desdeId == hastaId) return;
    final db = await AppDatabase.instance.database;
    await db.update(
      'productos',
      {'categoria_id': hastaId},
      where: 'categoria_id = ?',
      whereArgs: [desdeId],
    );
  }

  /// Borra la categoría. Solo se permite si no quedan productos usando la
  /// clave foránea; la interfaz ofrece moverlos antes.
  Future<void> deleteCategoria(int id) async {
    final db = await AppDatabase.instance.database;
    final enUso = await countProductosCategoria(id);
    if (enUso > 0) {
      throw StateError(
        'La categoría todavía tiene $enUso producto(s). Muévelos antes de eliminarla.',
      );
    }
    await db.delete('categorias_producto', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<UnidadMedida>> getUnidades() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'unidades_medida',
      where: 'activo = 1',
      orderBy: 'nombre COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => UnidadMedida(
            id: row['id']! as int,
            nombre: row['nombre']! as String,
            abreviatura: row['abreviatura']! as String,
            familia: (row['familia'] as String?) ?? 'OTRO',
            factorBase: (row['factor_base'] as num?)?.toDouble() ?? 1,
          ),
        )
        .toList();
  }

  Future<List<Producto>> getProductos({bool soloActivos = false}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.*, c.nombre AS categoria_nombre, c.color AS categoria_color,
             c.parent_id AS categoria_parent_id,
             cp.nombre AS categoria_parent_nombre,
             c.siempre_disponible AS categoria_siempre_disponible,
             iv.id AS insumo_vinculado_id,
             COALESCE(s.stock, 0) AS stock
      FROM productos p
      INNER JOIN categorias_producto c ON c.id = p.categoria_id
      LEFT JOIN categorias_producto cp ON cp.id = c.parent_id
      LEFT JOIN insumos iv ON iv.producto_id = p.id AND iv.venta_directa = 1
      LEFT JOIN v_stock_productos s ON s.producto_id = p.id
      ${soloActivos ? 'WHERE p.activo = 1' : ''}
      ORDER BY p.activo DESC, c.orden, p.nombre COLLATE NOCASE
    ''');
    return rows.map(_productFromRow).toList();
  }

  /// Productos directos activos: bebidas y snacks que se venden siempre.
  Future<List<Producto>> getProductosDirectosActivos() async {
    final productos = await getProductos(soloActivos: true);
    return productos.where((producto) => producto.esDirecto).toList();
  }

  /// Productos preparados activos: platos que se Arman con receta.
  Future<List<Producto>> getProductosPreparadosActivos() async {
    final productos = await getProductos(soloActivos: true);
    return productos.where((producto) => !producto.esDirecto).toList();
  }

  Future<Producto?> getProducto(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT p.*, c.nombre AS categoria_nombre, c.color AS categoria_color,
             c.parent_id AS categoria_parent_id,
             cp.nombre AS categoria_parent_nombre,
             c.siempre_disponible AS categoria_siempre_disponible,
             iv.id AS insumo_vinculado_id,
             COALESCE(s.stock, 0) AS stock
      FROM productos p
      INNER JOIN categorias_producto c ON c.id = p.categoria_id
      LEFT JOIN categorias_producto cp ON cp.id = c.parent_id
      LEFT JOIN insumos iv ON iv.producto_id = p.id AND iv.venta_directa = 1
      LEFT JOIN v_stock_productos s ON s.producto_id = p.id
      WHERE p.id = ?
      LIMIT 1
    ''',
      [id],
    );
    return rows.isEmpty ? null : _productFromRow(rows.first);
  }

  Future<int> saveProducto(Producto producto) async {
    final db = await AppDatabase.instance.database;
    final values = <String, Object?>{
      'nombre': producto.nombre.trim(),
      'categoria_id': producto.categoriaId,
      'descripcion': producto.descripcion?.trim().isEmpty == true
          ? null
          : producto.descripcion?.trim(),
      'precio': producto.precio,
      'imagen': producto.imagen,
      'tipo': producto.tipo,
      'es_compuesto': producto.esCompuesto ? 1 : 0,
      'stock_minimo': producto.esDirecto ? producto.stockMinimo : 0,
      'costo_unitario': producto.costoUnitario,
      'activo': producto.activo ? 1 : 0,
      'agotado': producto.agotado ? 1 : 0,
    };
    if (producto.id == null) {
      values['creado_en'] = sqlNow();
      return db.insert('productos', values);
    }
    await db.update(
      'productos',
      values,
      where: 'id = ?',
      whereArgs: [producto.id],
    );
    // Si el producto nace de un insumo de venta directa, el precio se mantiene
    // sincronizado para que el insumo muestre el valor correcto.
    await db.update(
      'insumos',
      {'precio_venta': producto.precio},
      where: 'producto_id = ?',
      whereArgs: [producto.id],
    );
    return producto.id!;
  }

  Future<void> setProductoActivo(int id, bool activo) async {
    final db = await AppDatabase.instance.database;
    final values = <String, Object?>{'activo': activo ? 1 : 0};
    // Al reactivar, el producto vuelve a estar disponible para la venta.
    if (activo) values['agotado'] = 0;
    await db.update(
      'productos',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (activo) {
      // Si el producto ya estaba en el menú de hoy, se rehabilita solo.
      await db.rawUpdate(
        '''
        UPDATE menu_dia_items
        SET disponible = 1, motivo_agotado = NULL
        WHERE producto_id = ?
          AND menu_dia_id IN (
            SELECT id FROM menus_dia WHERE fecha = ?
          )
        ''',
        [id, sqlDate(DateTime.now())],
      );
    }
  }

  /// Marca o limpia la bandera de agotado. Se usa desde Ventas (marcar) y
  /// desde el Menú del día (rehabilitar).
  Future<void> setProductoAgotado(int id, bool agotado) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'productos',
      {'agotado': agotado ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<ProductoComponente>> getComponentes(int productoId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT pc.componente_id, pc.cantidad, pc.orden,
             p.nombre, p.precio, p.imagen,
             c.nombre AS categoria_nombre, c.color AS categoria_color
      FROM producto_componentes pc
      INNER JOIN productos p ON p.id = pc.componente_id
      INNER JOIN categorias_producto c ON c.id = p.categoria_id
      WHERE pc.producto_id = ?
      ORDER BY pc.orden, p.nombre COLLATE NOCASE
    ''',
      [productoId],
    );
    return rows
        .map(
          (row) => ProductoComponente(
            componenteId: row['componente_id']! as int,
            nombre: row['nombre']! as String,
            precio: (row['precio'] as num).toDouble(),
            categoriaNombre: row['categoria_nombre']! as String,
            categoriaColor: (row['categoria_color'] as num).toInt(),
            cantidad: (row['cantidad'] as num?)?.toDouble() ?? 1,
            orden: (row['orden'] as num?)?.toInt() ?? 0,
            imagen: _asBytes(row['imagen']),
          ),
        )
        .toList();
  }

  Future<void> saveComponentes(int productoId, List<int> componenteIds) async {
    final db = await AppDatabase.instance.database;
    final ids = componenteIds.where((id) => id != productoId).toSet().toList();
    await db.transaction((txn) async {
      await txn.delete(
        'producto_componentes',
        where: 'producto_id = ?',
        whereArgs: [productoId],
      );
      var orden = 0;
      for (final componenteId in ids) {
        orden++;
        await txn.insert('producto_componentes', {
          'producto_id': productoId,
          'componente_id': componenteId,
          'cantidad': 1,
          'orden': orden,
        });
      }
    });
  }

  /// Crea un combo como producto normal: no descuenta stock ni insumos. Los
  /// componentes se guardan solo para mostrarlos en la ficha del combo.
  Future<int> crearCombo({
    required String nombre,
    required int categoriaId,
    required double precio,
    required List<int> componenteIds,
    Uint8List? imagen,
  }) async {
    final db = await AppDatabase.instance.database;
    final id = await db.insert('productos', {
      'nombre': nombre.trim(),
      'categoria_id': categoriaId,
      'descripcion': 'Combo armado con varios productos. No descuenta stock.',
      'precio': precio,
      'imagen': imagen,
      'tipo': 'PREPARADO',
      'es_compuesto': 0,
      'es_combo': 1,
      'stock_minimo': 0,
      'costo_unitario': 0,
      'activo': 1,
      'agotado': 0,
      'creado_en': sqlNow(),
    });
    await saveComponentes(id, componenteIds);
    return id;
  }

  Future<int> crearProductoCompuesto({
    required String nombre,
    required int categoriaId,
    required double precio,
    required List<int> componenteIds,
  }) async {
    final db = await AppDatabase.instance.database;
    final id = await db.insert('productos', {
      'nombre': nombre.trim(),
      'categoria_id': categoriaId,
      'descripcion': 'Almuerzo o combo armado con varios productos.',
      'precio': precio,
      'tipo': 'PREPARADO',
      'es_compuesto': 1,
      'stock_minimo': 0,
      'costo_unitario': 0,
      'activo': 1,
      'creado_en': sqlNow(),
    });
    await saveComponentes(id, componenteIds);
    return id;
  }

  Future<void> actualizarProductoCompuesto({
    required int productoId,
    required String nombre,
    required double precio,
    required List<int> componenteIds,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'productos',
      {
        'nombre': nombre.trim(),
        'precio': precio,
        'es_compuesto': 1,
        'tipo': 'PREPARADO',
        'activo': 1,
      },
      where: 'id = ?',
      whereArgs: [productoId],
    );
    await saveComponentes(productoId, componenteIds);
  }

  Future<List<RecetaLinea>> getReceta(int productoId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT r.insumo_id, i.nombre AS insumo_nombre,
             u.abreviatura AS unidad_abreviatura,
             r.cantidad,
             COALESCE(s.stock, 0) AS stock
      FROM receta_insumos r
      INNER JOIN insumos i ON i.id = r.insumo_id
      INNER JOIN unidades_medida u ON u.id = i.unidad_id
      LEFT JOIN v_stock_insumos s ON s.insumo_id = i.id
      WHERE r.producto_id = ?
      ORDER BY i.nombre COLLATE NOCASE
    ''',
      [productoId],
    );
    return rows
        .map(
          (row) => RecetaLinea(
            insumoId: row['insumo_id']! as int,
            insumoNombre: row['insumo_nombre']! as String,
            unidadAbreviatura: row['unidad_abreviatura']! as String,
            cantidad: (row['cantidad'] as num).toDouble(),
            stock: (row['stock'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<void> saveReceta(int productoId, List<RecetaLinea> lineas) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'receta_insumos',
        where: 'producto_id = ?',
        whereArgs: [productoId],
      );
      for (final linea in lineas) {
        await txn.insert('receta_insumos', {
          'producto_id': productoId,
          'insumo_id': linea.insumoId,
          'cantidad': linea.cantidad,
        });
      }
    });
  }

  Future<void> saveRecetaCantidades(
    int productoId,
    Map<int, double> cantidades,
  ) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'receta_insumos',
        where: 'producto_id = ?',
        whereArgs: [productoId],
      );
      for (final entry in cantidades.entries) {
        if (entry.value <= 0) continue;
        await txn.insert('receta_insumos', {
          'producto_id': productoId,
          'insumo_id': entry.key,
          'cantidad': entry.value,
        });
      }
    });
  }

  Future<List<Insumo>> getInsumos({bool soloActivos = false}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT i.*, u.abreviatura AS unidad_abreviatura,
             u.nombre AS unidad_nombre, u.familia AS unidad_familia,
             u.factor_base AS unidad_factor,
             p.categoria_id AS categoria_venta_id,
             p.imagen AS producto_imagen,
             COALESCE(s.stock, 0) AS stock
      FROM insumos i
      INNER JOIN unidades_medida u ON u.id = i.unidad_id
      LEFT JOIN productos p ON p.id = i.producto_id
      LEFT JOIN v_stock_insumos s ON s.insumo_id = i.id
      ${soloActivos ? 'WHERE i.activo = 1' : ''}
      ORDER BY i.activo DESC, i.nombre COLLATE NOCASE
    ''');
    return rows.map(_insumoFromRow).toList();
  }

  Future<Insumo?> getInsumo(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT i.*, u.abreviatura AS unidad_abreviatura,
             u.nombre AS unidad_nombre, u.familia AS unidad_familia,
             u.factor_base AS unidad_factor,
             p.categoria_id AS categoria_venta_id,
             p.imagen AS producto_imagen,
             COALESCE(s.stock, 0) AS stock
      FROM insumos i
      INNER JOIN unidades_medida u ON u.id = i.unidad_id
      LEFT JOIN productos p ON p.id = i.producto_id
      LEFT JOIN v_stock_insumos s ON s.insumo_id = i.id
      WHERE i.id = ?
      LIMIT 1
    ''',
      [id],
    );
    return rows.isEmpty ? null : _insumoFromRow(rows.first);
  }

  Future<Insumo?> getInsumoByNombre(String nombre) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT i.*, u.abreviatura AS unidad_abreviatura,
             u.nombre AS unidad_nombre, u.familia AS unidad_familia,
             u.factor_base AS unidad_factor,
             p.categoria_id AS categoria_venta_id,
             p.imagen AS producto_imagen,
             COALESCE(s.stock, 0) AS stock
      FROM insumos i
      INNER JOIN unidades_medida u ON u.id = i.unidad_id
      LEFT JOIN productos p ON p.id = i.producto_id
      LEFT JOIN v_stock_insumos s ON s.insumo_id = i.id
      WHERE LOWER(TRIM(i.nombre)) = LOWER(?)
      LIMIT 1
    ''',
      [nombre.trim()],
    );
    return rows.isEmpty ? null : _insumoFromRow(rows.first);
  }

  Future<int> saveInsumo(Insumo insumo) async {
    final db = await AppDatabase.instance.database;
    final values = <String, Object?>{
      'nombre': insumo.nombre.trim(),
      'unidad_id': insumo.unidadId,
      'modo_control': 'UNIDAD',
      'disponible': 1,
      'stock_minimo': insumo.stockMinimo,
      'costo_promedio': insumo.costoPromedio,
      'venta_directa': insumo.ventaDirecta ? 1 : 0,
      'precio_venta': insumo.precioVenta,
      'activo': insumo.activo ? 1 : 0,
      'consumible': insumo.consumible ? 1 : 0,
    };
    final int id;
    if (insumo.id == null) {
      id = await db.insert('insumos', values);
    } else {
      id = insumo.id!;
      await db.update('insumos', values, where: 'id = ?', whereArgs: [id]);
    }
    if (insumo.ventaDirecta) {
      await _sincronizarProductoVentaDirecta(insumoId: id, insumo: insumo);
    } else if (insumo.productoId != null) {
      // Se desactiva, no se borra: conserva el historial de ventas.
      await db.update(
        'productos',
        {'activo': 0},
        where: 'id = ?',
        whereArgs: [insumo.productoId],
      );
    }
    return id;
  }

  /// Crea o actualiza el producto que representa un insumo de venta directa.
  /// La receta siempre es una unidad del insumo.
  Future<void> _sincronizarProductoVentaDirecta({
    required int insumoId,
    required Insumo insumo,
  }) async {
    final db = await AppDatabase.instance.database;
    final categoriaId =
        insumo.categoriaVentaDirectaId ?? await _categoriaVentaDirectaId();
    final nombreInsumo = insumo.nombre.trim();
    int? productoId = insumo.productoId;
    if (productoId != null) {
      final existe = await db.query(
        'productos',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [productoId],
        limit: 1,
      );
      if (existe.isEmpty) productoId = null;
    }

    var nombre = nombreInsumo;
    if (productoId == null) {
      final ocupado = await db.query(
        'productos',
        columns: ['id'],
        where: 'nombre = ?',
        whereArgs: [nombre],
        limit: 1,
      );
      if (ocupado.isNotEmpty) nombre = '$nombreInsumo (venta directa)';
      productoId = await db.insert('productos', {
        'nombre': nombre,
        'categoria_id': categoriaId,
        'descripcion': 'Venta directa del insumo $nombreInsumo',
        'precio': insumo.precioVenta,
        'imagen': insumo.imagen,
        'tipo': 'PREPARADO',
        'stock_minimo': 0,
        'costo_unitario': 0,
        'activo': insumo.activo ? 1 : 0,
        'creado_en': sqlNow(),
      });
      await db.update(
        'insumos',
        {'producto_id': productoId},
        where: 'id = ?',
        whereArgs: [insumoId],
      );
    } else {
      final ocupado = await db.query(
        'productos',
        columns: ['id'],
        where: 'nombre = ? AND id <> ?',
        whereArgs: [nombre, productoId],
        limit: 1,
      );
      if (ocupado.isNotEmpty) nombre = '$nombreInsumo (venta directa)';
      final repetido = await db.query(
        'productos',
        columns: ['id'],
        where: 'nombre = ? AND id <> ?',
        whereArgs: [nombre, productoId],
        limit: 1,
      );
      if (repetido.isNotEmpty) nombre = '$nombreInsumo ($productoId)';
      await db.update(
        'productos',
        {
          'nombre': nombre,
          'categoria_id': categoriaId,
          'precio': insumo.precioVenta,
          'imagen': insumo.imagen,
          'tipo': 'PREPARADO',
          'stock_minimo': 0,
          'costo_unitario': 0,
          'activo': insumo.activo ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [productoId],
      );
    }
    await saveRecetaCantidades(productoId, {insumoId: 1});
  }

  /// Categoría (con `siempre_disponible = 1`) para los productos que se
  /// generan desde un insumo de venta directa.
  Future<int> _categoriaVentaDirectaId() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'categorias_producto',
      columns: ['id'],
      where: 'nombre = ? COLLATE NOCASE',
      whereArgs: ['Venta directa'],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final id = rows.first['id'] as int;
      await db.update(
        'categorias_producto',
        {'nombre': 'VENTA DIRECTA', 'siempre_disponible': 1, 'activo': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    return db.insert('categorias_producto', {
      'nombre': 'VENTA DIRECTA',
      'color': 0xFF0F766E,
      'siempre_disponible': 1,
      'orden': 90,
      'activo': 1,
    });
  }

  Future<void> setInsumoActivo(int id, bool activo) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'insumos',
      {'activo': activo ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<double> getStockInsumo(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'v_stock_insumos',
      columns: ['stock'],
      where: 'insumo_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? 0 : (rows.first['stock'] as num).toDouble();
  }

  Future<double> getStockProducto(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'v_stock_productos',
      columns: ['stock'],
      where: 'producto_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? 0 : (rows.first['stock'] as num).toDouble();
  }

  Future<String?> motivoNoDisponible(
    int productoId,
    double cantidad, {
    Producto? producto,
  }) => _motivoNoDisponible(productoId, cantidad, <int>{}, producto: producto);

  Future<String?> _motivoNoDisponible(
    int productoId,
    double cantidad,
    Set<int> visitados, {
    Producto? producto,
  }) async {
    if (!visitados.add(productoId)) return null;
    final actual = producto ?? await getProducto(productoId);
    if (actual == null || !actual.activo) return 'Producto inactivo';
    if (actual.agotado) return 'Agotado';
    if (actual.esDirecto) {
      if (actual.stock < cantidad) {
        return 'Sin stock (quedan ${actual.stock.toStringAsFixed(0)})';
      }
    }
    if (actual.esCompuesto) {
      for (final componente in await getComponentes(productoId)) {
        final motivo = await _motivoNoDisponible(
          componente.componenteId,
          cantidad * componente.cantidad,
          visitados,
        );
        if (motivo != null) return '${componente.nombre}: $motivo';
      }
    }
    // Los productos con receta no se bloquean por falta de insumos: la receta
    // solo controla el consumo y el faltante se registra al vender.
    return null;
  }

  /// Aviso no bloqueante cuando un producto con receta no tiene insumos
  /// suficientes. Los productos sin receta no generan advertencias.
  /// Se puede pasar el producto ya cargado para evitar otra consulta.
  Future<String?> advertenciaInsumos(
    int productoId,
    double cantidad, {
    Producto? producto,
  }) async {
    final actual = producto ?? await getProducto(productoId);
    if (actual == null) return null;
    if (actual.esCompuesto) {
      final faltantes = <String>[];
      for (final componente in await getComponentes(productoId)) {
        final aviso = await advertenciaInsumos(
          componente.componenteId,
          cantidad * componente.cantidad,
        );
        if (aviso != null) faltantes.add(aviso);
      }
      return faltantes.isEmpty
          ? null
          : 'Faltan insumos en: ${faltantes.join(' · ')}';
    }
    final receta = await getReceta(productoId);
    if (receta.isEmpty) return null;
    final faltantes = <String>[];
    for (final linea in receta) {
      if (linea.stock < linea.cantidad * cantidad) {
        faltantes.add(linea.insumoNombre);
      }
    }
    if (faltantes.isEmpty) return null;
    return 'Faltan insumos: ${faltantes.join(', ')}';
  }

  /// Fija el stock real de un insumo guardando la diferencia como ajuste.
  Future<void> ajustarStockInsumo({
    required int insumoId,
    required double nuevoStock,
    required int usuarioId,
    String? motivo,
  }) async {
    final actual = await getStockInsumo(insumoId);
    final diferencia = nuevoStock - actual;
    if (diferencia.abs() < 0.0001) return;
    final db = await AppDatabase.instance.database;
    await db.insert('ajustes_stock', {
      'fecha': sqlNow(),
      'insumo_id': insumoId,
      'producto_id': null,
      'cantidad': diferencia,
      'motivo': motivo,
      'usuario_id': usuarioId,
    });
  }

  /// Fija el stock real de un producto directo guardando la diferencia.
  Future<void> ajustarStockProducto({
    required int productoId,
    required double nuevoStock,
    required int usuarioId,
    String? motivo,
  }) async {
    final actual = await getStockProducto(productoId);
    final diferencia = nuevoStock - actual;
    if (diferencia.abs() < 0.0001) return;
    final db = await AppDatabase.instance.database;
    await db.insert('ajustes_stock', {
      'fecha': sqlNow(),
      'insumo_id': null,
      'producto_id': productoId,
      'cantidad': diferencia,
      'motivo': motivo,
      'usuario_id': usuarioId,
    });
  }

  /// Presentaciones activas agrupadas por producto base.
  Future<Map<int, List<ProductoPresentacion>>> getPresentaciones() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'producto_presentaciones',
      where: 'activo = 1',
      orderBy: 'orden, id',
    );
    final map = <int, List<ProductoPresentacion>>{};
    for (final row in rows) {
      final presentacion = ProductoPresentacion(
        id: row['id']! as int,
        productoId: row['producto_id']! as int,
        nombre: row['nombre']! as String,
        precio: (row['precio'] as num).toDouble(),
        orden: (row['orden'] as num?)?.toInt() ?? 0,
        activo: (row['activo'] as num).toInt() == 1,
        imagen: _asBytes(row['imagen']),
      );
      map.putIfAbsent(presentacion.productoId, () => []).add(presentacion);
    }
    return map;
  }

  /// Presentaciones (activas e inactivas) de un producto, para editarlas.
  Future<List<ProductoPresentacion>> getPresentacionesDe(int productoId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'producto_presentaciones',
      where: 'producto_id = ?',
      whereArgs: [productoId],
      orderBy: 'orden, id',
    );
    return rows
        .map(
          (row) => ProductoPresentacion(
            id: row['id']! as int,
            productoId: row['producto_id']! as int,
            nombre: row['nombre']! as String,
            precio: (row['precio'] as num).toDouble(),
            orden: (row['orden'] as num?)?.toInt() ?? 0,
            activo: (row['activo'] as num).toInt() == 1,
            imagen: _asBytes(row['imagen']),
          ),
        )
        .toList();
  }

  Future<int> savePresentacion(ProductoPresentacion presentacion) async {
    final db = await AppDatabase.instance.database;
    final values = <String, Object?>{
      'producto_id': presentacion.productoId,
      'nombre': presentacion.nombre.trim(),
      'precio': presentacion.precio,
      'imagen': presentacion.imagen,
      'orden': presentacion.orden,
      'activo': presentacion.activo ? 1 : 0,
    };
    if (presentacion.id == null) {
      return db.insert('producto_presentaciones', values);
    }
    await db.update(
      'producto_presentaciones',
      values,
      where: 'id = ?',
      whereArgs: [presentacion.id],
    );
    return presentacion.id!;
  }

  Future<void> eliminarPresentacion(int id) async {
    final db = await AppDatabase.instance.database;
    await db.delete(
      'producto_presentaciones',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Producto _productFromRow(Map<String, Object?> row) => Producto(
    id: row['id']! as int,
    nombre: row['nombre']! as String,
    categoriaId: row['categoria_id']! as int,
    categoriaNombre: row['categoria_nombre']! as String,
    categoriaColor: row['categoria_color']! as int,
    categoriaParentId: row['categoria_parent_id'] as int?,
    categoriaParentNombre: row['categoria_parent_nombre'] as String?,
    descripcion: row['descripcion'] as String?,
    precio: (row['precio'] as num).toDouble(),
    imagen: _asBytes(row['imagen']),
    tipo: row['tipo']! as String,
    stockMinimo: (row['stock_minimo'] as num).toDouble(),
    costoUnitario: (row['costo_unitario'] as num).toDouble(),
    activo: (row['activo'] as num).toInt() == 1,
    stock: (row['stock'] as num?)?.toDouble() ?? 0,
    agotado: (row['agotado'] as num?)?.toInt() == 1,
    esCombo:
        (row['es_combo'] as num?)?.toInt() == 1 ||
        (row['categoria_nombre'] as String?)?.trim().toUpperCase() == 'COMBOS',
    categoriaSiempreDisponible:
        (row['categoria_siempre_disponible'] as num?)?.toInt() == 1,
    insumoVinculadoId: row['insumo_vinculado_id'] as int?,
    esCompuesto: (row['es_compuesto'] as num?)?.toInt() == 1,
  );

  Insumo _insumoFromRow(Map<String, Object?> row) => Insumo(
    id: row['id']! as int,
    nombre: row['nombre']! as String,
    unidadId: row['unidad_id']! as int,
    unidadAbreviatura: row['unidad_abreviatura']! as String,
    unidadNombre: (row['unidad_nombre'] as String?) ?? '',
    unidadFamilia: (row['unidad_familia'] as String?) ?? 'OTRO',
    unidadFactorBase: (row['unidad_factor'] as num?)?.toDouble() ?? 1,
    stockMinimo: (row['stock_minimo'] as num).toDouble(),
    costoPromedio: (row['costo_promedio'] as num).toDouble(),
    activo: (row['activo'] as num).toInt() == 1,
    stock: (row['stock'] as num).toDouble(),
    ventaDirecta: (row['venta_directa'] as num?)?.toInt() == 1,
    precioVenta: (row['precio_venta'] as num?)?.toDouble() ?? 0,
    productoId: row['producto_id'] as int?,
    categoriaVentaDirectaId: row['categoria_venta_id'] as int?,
    imagen: _asBytes(row['producto_imagen']),
    consumible: (row['consumible'] as num?)?.toInt() != 0,
  );

  static Uint8List? _asBytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }
}
