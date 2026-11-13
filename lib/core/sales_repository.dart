import 'package:sqflite/sqflite.dart';

import '../data/database/app_database.dart';
import 'catalog_repository.dart';
import 'date_utils.dart';

class PagoInput {
  const PagoInput({required this.metodo, required this.monto, this.referencia});

  final String metodo;
  final double monto;
  final String? referencia;
}

class CartLine {
  const CartLine({
    required this.productoId,
    this.menuDiaItemId,
    this.menuDiaComboId,
    required this.nombre,
    required this.precio,
    required this.cantidad,
    this.observacion,
    this.tipo = 'PREPARADO',
    this.costoUnitario = 0,
  });

  final int productoId;
  final int? menuDiaItemId;
  final int? menuDiaComboId;
  final String nombre;
  final double precio;
  final double cantidad;
  final String? observacion;
  final String tipo;
  final double costoUnitario;

  double get subtotal => precio * cantidad;

  CartLine copyWith({double? cantidad, String? observacion}) => CartLine(
    productoId: productoId,
    menuDiaItemId: menuDiaItemId,
    menuDiaComboId: menuDiaComboId,
    nombre: nombre,
    precio: precio,
    cantidad: cantidad ?? this.cantidad,
    observacion: observacion ?? this.observacion,
    tipo: tipo,
    costoUnitario: costoUnitario,
  );
}

class Pedido {
  const Pedido({
    required this.id,
    this.referencia,
    required this.estadoPago,
    required this.estadoEntrega,
    required this.total,
    required this.pagado,
    required this.fecha,
    required this.usuarioNombre,
    required this.cajaId,
    this.menuDiaId,
    this.observacion,
  });

  final int id;
  final String? referencia;
  final String estadoPago;
  final String estadoEntrega;
  final double total;
  final double pagado;
  final String fecha;
  final String usuarioNombre;
  final int cajaId;
  final int? menuDiaId;
  final String? observacion;

  double get saldo => (total - pagado).clamp(0, double.infinity);
  bool get pagadoCompleto => estadoPago == 'PAGADO';
  bool get anulado => estadoPago == 'ANULADO' || estadoEntrega == 'ANULADO';
}

class PedidoLinea {
  const PedidoLinea({
    required this.id,
    required this.productoId,
    this.menuDiaItemId,
    required this.nombre,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
    this.observacion,
    this.esComponente = false,
  });

  final int id;
  final int productoId;
  final int? menuDiaItemId;
  final String nombre;
  final double cantidad;
  final double precioUnitario;
  final double subtotal;
  final String? observacion;
  final bool esComponente;
}

class Pago {
  const Pago({
    required this.id,
    required this.monto,
    required this.metodo,
    required this.estado,
    required this.fecha,
    this.referencia,
  });

  final int id;
  final double monto;
  final String metodo;
  final String estado;
  final String fecha;
  final String? referencia;
}

class PedidoDetalle {
  const PedidoDetalle({
    required this.pedido,
    required this.lineas,
    required this.pagos,
  });

  final Pedido pedido;
  final List<PedidoLinea> lineas;
  final List<Pago> pagos;
}

class SalesRepository {
  Future<List<Pedido>> getPedidosAbiertos() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.*, u.nombre AS usuario_nombre,
             COALESCE((SELECT SUM(monto) FROM pagos
                       WHERE pedido_id = p.id AND estado = 'CONFIRMADO'), 0) AS pagado
      FROM pedidos p
      INNER JOIN usuarios u ON u.id = p.usuario_id
      WHERE p.estado_pago = 'PENDIENTE'
        AND p.estado_entrega <> 'ANULADO'
      ORDER BY p.fecha DESC
      LIMIT 50
    ''');
    return rows.map(_pedidoFromRow).toList();
  }

  Future<List<Pedido>> getPedidosDelDia(DateTime fecha) async {
    final db = await AppDatabase.instance.database;
    final inicio = DateTime(fecha.year, fecha.month, fecha.day);
    final fin = inicio.add(const Duration(days: 1));
    final rows = await db.rawQuery(
      '''
      SELECT p.*, u.nombre AS usuario_nombre,
             COALESCE((SELECT SUM(monto) FROM pagos
                       WHERE pedido_id = p.id AND estado = 'CONFIRMADO'), 0) AS pagado
      FROM pedidos p
      INNER JOIN usuarios u ON u.id = p.usuario_id
      WHERE p.fecha >= ? AND p.fecha < ?
      ORDER BY p.fecha DESC
    ''',
      [sqlDateTime(inicio), sqlDateTime(fin)],
    );
    return rows.map(_pedidoFromRow).toList();
  }

  Future<PedidoDetalle> getPedido(int pedidoId) async {
    final db = await AppDatabase.instance.database;
    final pedidoRows = await db.rawQuery(
      '''
      SELECT p.*, u.nombre AS usuario_nombre,
             COALESCE((SELECT SUM(monto) FROM pagos
                       WHERE pedido_id = p.id AND estado = 'CONFIRMADO'), 0) AS pagado
      FROM pedidos p
      INNER JOIN usuarios u ON u.id = p.usuario_id
      WHERE p.id = ?
      LIMIT 1
    ''',
      [pedidoId],
    );
    if (pedidoRows.isEmpty) throw StateError('El pedido no existe.');
    final lineas = await db.query(
      'detalle_pedido',
      where: 'pedido_id = ?',
      whereArgs: [pedidoId],
      orderBy: 'id',
    );
    final pagos = await db.query(
      'pagos',
      where: 'pedido_id = ?',
      whereArgs: [pedidoId],
      orderBy: 'id',
    );
    return PedidoDetalle(
      pedido: _pedidoFromRow(pedidoRows.first),
      lineas: lineas
          .map(
            (row) => PedidoLinea(
              id: row['id']! as int,
              productoId: row['producto_id']! as int,
              menuDiaItemId: row['menu_dia_item_id'] as int?,
              nombre: row['nombre_producto']! as String,
              cantidad: (row['cantidad'] as num).toDouble(),
              precioUnitario: (row['precio_unitario'] as num).toDouble(),
               subtotal: (row['subtotal'] as num).toDouble(),
               observacion: row['observacion'] as String?,
               esComponente: (row['es_componente'] as num?)?.toInt() == 1,
             ),
          )
          .toList(),
      pagos: pagos
          .map(
            (row) => Pago(
              id: row['id']! as int,
              monto: (row['monto'] as num).toDouble(),
              metodo: row['metodo_pago']! as String,
              estado: row['estado']! as String,
              fecha: row['fecha']! as String,
              referencia: row['referencia'] as String?,
            ),
          )
          .toList(),
    );
  }

  Future<int> crearPedido({
    required int usuarioId,
    required int cajaId,
    int? menuDiaId,
    String? referencia,
    String? observacion,
    required List<CartLine> lineas,
    required List<PagoInput> pagos,
  }) async {
    if (lineas.isEmpty) {
      throw StateError('Agrega al menos un producto al pedido.');
    }
    final db = await AppDatabase.instance.database;
    await _validarCajaAbierta(db, cajaId);
    final resueltas = await _resolverLineas(db, lineas);
    await _validarDisponibilidad(resueltas);
    final total = resueltas.fold<double>(0, (sum, line) => sum + line.subtotal);
    final pagosValidos = pagos
        .where((pago) => pago.monto > 0)
        .toList(growable: false);
    await _validarMetodosPago(db, null, pagosValidos);
    final pagado = pagosValidos.fold<double>(
      0,
      (sum, pago) => sum + pago.monto,
    );
    if (pagado > total + 0.05) {
      throw StateError('El pago supera el total del pedido.');
    }
    final estadoPago = pagado + 0.001 >= total ? 'PAGADO' : 'PENDIENTE';
    final ahora = sqlNow();

    return db.transaction((txn) async {
      final pedidoId = await txn.insert('pedidos', {
        'referencia': _limpiar(referencia),
        'usuario_id': usuarioId,
        'caja_id': cajaId,
        'menu_dia_id': menuDiaId,
        'fecha': ahora,
        'estado_pago': estadoPago,
        'estado_entrega': 'PENDIENTE',
        'total': total,
        'observacion': _limpiar(observacion),
      });
      for (final linea in resueltas) {
        final detalleId = await txn.insert('detalle_pedido', {
          'pedido_id': pedidoId,
          'producto_id': linea.productoId,
          'menu_dia_item_id': linea.menuDiaItemId,
          'nombre_producto': linea.nombre,
          'cantidad': linea.cantidad,
          'precio_unitario': linea.precio,
          'subtotal': linea.subtotal,
          'costo_unitario': linea.costoUnitario,
          'es_componente': 0,
          'observacion': _limpiar(linea.observacion),
        });
        await _consumirProducto(
          txn,
          productoId: linea.productoId,
          cantidad: linea.cantidad,
          pedidoId: pedidoId,
          detalleId: detalleId,
          fecha: ahora,
        );
      }
      for (final pago in pagosValidos) {
        await txn.insert('pagos', {
          'pedido_id': pedidoId,
          'caja_id': cajaId,
          'usuario_id': usuarioId,
          'fecha': ahora,
          'monto': pago.monto,
          'metodo_pago': pago.metodo,
          'estado': 'CONFIRMADO',
          'referencia': _limpiar(pago.referencia),
        });
      }
      return pedidoId;
    });
  }

  Future<void> agregarLineas(
    int pedidoId,
    List<CartLine> lineas, {
    int? cajaId,
  }) async {
    if (lineas.isEmpty) return;
    final db = await AppDatabase.instance.database;
    final pedido = (await getPedido(pedidoId)).pedido;
    if (pedido.anulado) throw StateError('El pedido está anulado.');
    await _validarCajaAbierta(db, cajaId ?? pedido.cajaId);
    final resueltas = await _resolverLineas(db, lineas);
    await _validarDisponibilidad(resueltas);
    final adicional = resueltas.fold<double>(
      0,
      (sum, line) => sum + line.subtotal,
    );
    final ahora = sqlNow();
    await db.transaction((txn) async {
      for (final linea in resueltas) {
        final detalleId = await txn.insert('detalle_pedido', {
          'pedido_id': pedidoId,
          'producto_id': linea.productoId,
          'menu_dia_item_id': linea.menuDiaItemId,
          'nombre_producto': linea.nombre,
          'cantidad': linea.cantidad,
          'precio_unitario': linea.precio,
          'subtotal': linea.subtotal,
          'costo_unitario': linea.costoUnitario,
          'es_componente': 0,
          'observacion': _limpiar(linea.observacion),
        });
        await _consumirProducto(
          txn,
          productoId: linea.productoId,
          cantidad: linea.cantidad,
          pedidoId: pedidoId,
          detalleId: detalleId,
          fecha: ahora,
        );
      }
      final nuevoTotal = pedido.total + adicional;
      await txn.update(
        'pedidos',
        {
          'total': nuevoTotal,
          'estado_pago': pedido.pagado + 0.001 >= nuevoTotal
              ? 'PAGADO'
              : 'PENDIENTE',
        },
        where: 'id = ?',
        whereArgs: [pedidoId],
      );
    });
  }

  Future<void> agregarPagos({
    required int pedidoId,
    required int usuarioId,
    int? cajaId,
    required List<PagoInput> pagos,
  }) async {
    final validos = pagos.where((pago) => pago.monto > 0).toList();
    if (validos.isEmpty) return;
    final db = await AppDatabase.instance.database;
    final detalle = await getPedido(pedidoId);
    final pedido = detalle.pedido;
    if (pedido.anulado) throw StateError('El pedido está anulado.');
    final cajaDestino = cajaId ?? pedido.cajaId;
    await _validarCajaAbierta(db, cajaDestino);
    await _validarMetodosPago(db, pedidoId, validos);
    final nuevoPagado =
        pedido.pagado +
        validos.fold<double>(0, (sum, pago) => sum + pago.monto);
    if (nuevoPagado > pedido.total + 0.05) {
      throw StateError('El pago supera el saldo del pedido.');
    }
    final ahora = sqlNow();
    await db.transaction((txn) async {
      for (final pago in validos) {
        await txn.insert('pagos', {
          'pedido_id': pedidoId,
          'caja_id': cajaDestino,
          'usuario_id': usuarioId,
          'fecha': ahora,
          'monto': pago.monto,
          'metodo_pago': pago.metodo,
          'estado': 'CONFIRMADO',
          'referencia': _limpiar(pago.referencia),
        });
      }
      await txn.update(
        'pedidos',
        {
          'estado_pago': nuevoPagado + 0.001 >= pedido.total
              ? 'PAGADO'
              : 'PENDIENTE',
        },
        where: 'id = ?',
        whereArgs: [pedidoId],
      );
    });
  }

  Future<void> anularPedido(int pedidoId) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.update(
        'pedidos',
        {'estado_pago': 'ANULADO', 'estado_entrega': 'ANULADO'},
        where: 'id = ?',
        whereArgs: [pedidoId],
      );
      await txn.update(
        'pagos',
        {'estado': 'ANULADO'},
        where: 'pedido_id = ?',
        whereArgs: [pedidoId],
      );
      await txn.update(
        'consumos_insumo',
        {'estado': 'ANULADO'},
        where: 'pedido_id = ?',
        whereArgs: [pedidoId],
      );
      await txn.update(
        'faltantes_insumo',
        {'estado': 'ANULADO'},
        where: 'pedido_id = ?',
        whereArgs: [pedidoId],
      );
    });
  }

  Future<void> marcarEntrega(int pedidoId, String estado) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'pedidos',
      {'estado_entrega': estado},
      where: 'id = ?',
      whereArgs: [pedidoId],
    );
  }

  Future<List<CartLine>> _resolverLineas(
    Database db,
    List<CartLine> lineas,
  ) async {
    final result = <CartLine>[];
    for (final linea in lineas) {
      if (linea.menuDiaComboId != null) {
        final comboRows = await db.rawQuery(
          '''
          SELECT mc.producto_id, mc.nombre, mc.precio, mc.disponible,
                 p.tipo, p.costo_unitario, p.activo
          FROM menu_dia_combos mc
          INNER JOIN productos p ON p.id = mc.producto_id
          WHERE mc.id = ?
          LIMIT 1
        ''',
          [linea.menuDiaComboId],
        );
        if (comboRows.isEmpty) {
          throw StateError('El combo del pedido ya no existe.');
        }
        final combo = comboRows.first;
        if ((combo['activo'] as num).toInt() != 1) {
          throw StateError('El combo ${combo['nombre']} está inactivo.');
        }
        if ((combo['disponible'] as num).toInt() != 1) {
          throw StateError('El combo ${combo['nombre']} está agotado hoy.');
        }
        result.add(
          CartLine(
            productoId: combo['producto_id']! as int,
            menuDiaComboId: linea.menuDiaComboId,
            nombre: combo['nombre']! as String,
            precio: (combo['precio'] as num).toDouble(),
            cantidad: linea.cantidad,
            observacion: linea.observacion,
            tipo: combo['tipo']! as String,
            costoUnitario: (combo['costo_unitario'] as num).toDouble(),
          ),
        );
        continue;
      }
      final rows = await db.query(
        'productos',
        columns: ['nombre', 'precio', 'tipo', 'costo_unitario', 'activo'],
        where: 'id = ?',
        whereArgs: [linea.productoId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Un producto del pedido ya no existe.');
      }
      final row = rows.first;
      if ((row['activo'] as num).toInt() != 1) {
        throw StateError('El producto ${row['nombre']} está inactivo.');
      }
      if (linea.menuDiaItemId != null) {
        final menuRows = await db.query(
          'menu_dia_items',
          columns: ['disponible'],
          where: 'id = ?',
          whereArgs: [linea.menuDiaItemId],
          limit: 1,
        );
        if (menuRows.isEmpty ||
            (menuRows.first['disponible'] as num).toInt() != 1) {
          throw StateError('El producto ${row['nombre']} está agotado hoy.');
        }
      }
      result.add(
        CartLine(
          productoId: linea.productoId,
          menuDiaItemId: linea.menuDiaItemId,
          nombre: row['nombre']! as String,
          precio: (row['precio'] as num).toDouble(),
          cantidad: linea.cantidad,
          observacion: linea.observacion,
          tipo: row['tipo']! as String,
          costoUnitario: (row['costo_unitario'] as num).toDouble(),
        ),
      );
    }
    return result;
  }

  Future<void> _validarDisponibilidad(List<CartLine> lineas) async {
    final cantidades = <int, double>{};
    for (final linea in lineas) {
      cantidades.update(
        linea.productoId,
        (value) => value + linea.cantidad,
        ifAbsent: () => linea.cantidad,
      );
    }
    final catalog = CatalogRepository();
    for (final entry in cantidades.entries) {
      final motivo = await catalog.motivoNoDisponible(entry.key, entry.value);
      if (motivo != null) {
        final nombre = lineas
            .firstWhere((linea) => linea.productoId == entry.key)
            .nombre;
        throw StateError('$nombre: $motivo');
      }
    }
  }

  /// Consume una línea del pedido. Si el producto es compuesto, recorre sus
  /// componentes y registra una línea hija por cada uno. Así el stock de los
  /// productos directos se descuenta y las recetas de los preparados se
  /// consumen sin obligar a ningún producto a tener receta.
  Future<void> _consumirProducto(
    DatabaseExecutor txn, {
    required int productoId,
    required double cantidad,
    required int pedidoId,
    required int detalleId,
    required String fecha,
    Set<int>? visitados,
  }) async {
    final vistos = visitados ?? <int>{};
    if (!vistos.add(productoId)) return;
    final rows = await txn.query(
      'productos',
      columns: ['es_compuesto'],
      where: 'id = ?',
      whereArgs: [productoId],
      limit: 1,
    );
    final compuesto =
        rows.isNotEmpty &&
        ((rows.first['es_compuesto'] as num?)?.toInt() ?? 0) == 1;
    if (!compuesto) {
      await _consumirReceta(
        txn,
        productoId: productoId,
        cantidad: cantidad,
        pedidoId: pedidoId,
        detalleId: detalleId,
        fecha: fecha,
      );
      return;
    }
    final componentes = await txn.rawQuery(
      '''
      SELECT pc.componente_id, pc.cantidad, p.nombre, p.costo_unitario
      FROM producto_componentes pc
      INNER JOIN productos p ON p.id = pc.componente_id
      WHERE pc.producto_id = ?
      ORDER BY pc.orden
    ''',
      [productoId],
    );
    for (final componente in componentes) {
      final componenteId = componente['componente_id']! as int;
      final cantidadComponente =
          (componente['cantidad'] as num).toDouble() * cantidad;
      final componenteDetalleId = await txn.insert('detalle_pedido', {
        'pedido_id': pedidoId,
        'producto_id': componenteId,
        'menu_dia_item_id': null,
        'nombre_producto': componente['nombre']! as String,
        'cantidad': cantidadComponente,
        'precio_unitario': 0,
        'subtotal': 0,
        'costo_unitario': (componente['costo_unitario'] as num).toDouble(),
        'es_componente': 1,
        'observacion': null,
      });
      await _consumirProducto(
        txn,
        productoId: componenteId,
        cantidad: cantidadComponente,
        pedidoId: pedidoId,
        detalleId: componenteDetalleId,
        fecha: fecha,
        visitados: vistos,
      );
    }
  }

  Future<void> _consumirReceta(
    DatabaseExecutor txn, {
    required int productoId,
    required double cantidad,
    required int pedidoId,
    required int detalleId,
    required String fecha,
  }) async {
    final receta = await txn.rawQuery(
      '''
      SELECT r.insumo_id, r.cantidad, i.costo_promedio
      FROM receta_insumos r
      INNER JOIN insumos i ON i.id = r.insumo_id
      WHERE r.producto_id = ?
    ''',
      [productoId],
    );
    for (final row in receta) {
      final insumoId = row['insumo_id']! as int;
      final requerido = (row['cantidad'] as num).toDouble() * cantidad;
      final costo = (row['costo_promedio'] as num).toDouble();
      final stockRows = await txn.query(
        'v_stock_insumos',
        columns: ['stock'],
        where: 'insumo_id = ?',
        whereArgs: [insumoId],
        limit: 1,
      );
      final stockActual = stockRows.isEmpty
          ? 0.0
          : (stockRows.first['stock'] as num).toDouble();
      final disponible = stockActual > 0 ? stockActual : 0.0;
      final consumido = requerido < disponible ? requerido : disponible;
      if (consumido > 0) {
        await txn.insert('consumos_insumo', {
          'insumo_id': insumoId,
          'pedido_id': pedidoId,
          'detalle_pedido_id': detalleId,
          'fecha': fecha,
          'cantidad': consumido,
          'costo_unitario': costo,
          'estado': 'CONFIRMADO',
        });
      }
      final faltante = requerido - disponible;
      if (faltante > 0.000001) {
        await txn.insert('faltantes_insumo', {
          'fecha': fecha,
          'pedido_id': pedidoId,
          'detalle_pedido_id': detalleId,
          'producto_id': productoId,
          'insumo_id': insumoId,
          'cantidad_requerida': requerido,
          'cantidad_disponible': disponible,
          'cantidad_consumida': consumido,
          'cantidad_faltante': faltante,
          'costo_unitario': costo,
          'estado': 'CONFIRMADO',
        });
      }
    }
  }

  Future<void> _validarMetodosPago(
    Database db,
    int? pedidoId,
    List<PagoInput> pagos,
  ) async {
    final metodos = <String>{};
    if (pedidoId != null) {
      final rows = await db.query(
        'pagos',
        columns: ['metodo_pago'],
        where: "pedido_id = ? AND estado = 'CONFIRMADO'",
        whereArgs: [pedidoId],
      );
      metodos.addAll(rows.map((row) => row['metodo_pago']! as String));
    }
    metodos.addAll(
      pagos.where((pago) => pago.monto > 0).map((pago) => pago.metodo),
    );
    if (metodos.length > 2) {
      throw StateError(
        'Un pedido admite como máximo dos métodos de pago (efectivo y QR).',
      );
    }
  }

  Future<void> _validarCajaAbierta(Database db, int cajaId) async {
    final rows = await db.query(
      'cajas',
      columns: ['estado'],
      where: 'id = ?',
      whereArgs: [cajaId],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['estado'] != 'ABIERTA') {
      throw StateError('La caja está cerrada. Abre una caja para vender.');
    }
  }

  Pedido _pedidoFromRow(Map<String, Object?> row) => Pedido(
    id: row['id']! as int,
    referencia: row['referencia'] as String?,
    estadoPago: row['estado_pago']! as String,
    estadoEntrega: row['estado_entrega']! as String,
    total: (row['total'] as num).toDouble(),
    pagado: (row['pagado'] as num?)?.toDouble() ?? 0,
    fecha: row['fecha']! as String,
    usuarioNombre: (row['usuario_nombre'] as String?) ?? '',
    cajaId: row['caja_id']! as int,
    menuDiaId: row['menu_dia_id'] as int?,
    observacion: row['observacion'] as String?,
  );

  String? _limpiar(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
