import '../data/database/app_database.dart';
import 'date_utils.dart';

class ResumenFinanciero {
  const ResumenFinanciero({
    required this.ventas,
    required this.cobrosEfectivo,
    required this.cobrosQr,
    required this.gastoInsumos,
    required this.salidas,
    required this.salidasEfectivo,
    required this.salidasQr,
    required this.pedidos,
  });

  final double ventas;
  final double cobrosEfectivo;
  final double cobrosQr;
  final double gastoInsumos;
  final double salidas;
  final double salidasEfectivo;
  final double salidasQr;
  final int pedidos;

  double get cobros => cobrosEfectivo + cobrosQr;
  double get ganancia => ventas - gastoInsumos - salidas;
  double get ticketPromedio => pedidos == 0 ? 0 : ventas / pedidos;
}

class ProductoReporte {
  const ProductoReporte({
    required this.nombre,
    required this.cantidad,
    required this.ventas,
    required this.costo,
    required this.color,
    this.precioUnitario = 0,
  });

  final String nombre;
  final double cantidad;
  final double ventas;
  final double costo;
  final int color;
  final double precioUnitario;

  double get ganancia => ventas - costo;
}

class SalidaReporte {
  const SalidaReporte({
    required this.fecha,
    required this.detalle,
    required this.metodoPago,
    required this.monto,
    required this.usuario,
    required this.turno,
  });

  final DateTime fecha;
  final String detalle;
  final String metodoPago;
  final double monto;
  final String usuario;
  final int turno;

  String get turnoLabel => turno == 0 ? '—' : 'Turno $turno';
}

class PedidoReporte {
  const PedidoReporte({
    required this.id,
    required this.fecha,
    required this.referencia,
    required this.usuario,
    required this.numeroTurno,
    required this.total,
    required this.efectivo,
    required this.qr,
    required this.estadoPago,
    required this.estadoEntrega,
  });

  final int id;
  final String fecha;
  final String? referencia;
  final String usuario;
  final int numeroTurno;
  final double total;
  final double efectivo;
  final double qr;
  final String estadoPago;
  final String estadoEntrega;

  double get pagado => efectivo + qr;
  String get turnoLabel => 'Turno $numeroTurno';
}

class GastoReporte {
  const GastoReporte({required this.nombre, required this.total});

  final String nombre;
  final double total;
}

class InventarioReporte {
  const InventarioReporte({
    required this.nombre,
    required this.tipo,
    required this.modoControl,
    required this.stock,
    required this.stockMinimo,
    required this.costoUnitario,
    required this.alerta,
  });

  final String nombre;
  final String tipo;
  final String? modoControl;
  final double stock;
  final double stockMinimo;
  final double costoUnitario;
  final bool alerta;

  double get valor => stock * costoUnitario;
}

class FaltanteInsumoReporte {
  const FaltanteInsumoReporte({
    required this.fecha,
    required this.referencia,
    required this.producto,
    required this.insumo,
    required this.unidad,
    required this.requerido,
    required this.disponible,
    required this.consumido,
    required this.faltante,
    required this.costoUnitario,
  });

  final DateTime fecha;
  final String? referencia;
  final String producto;
  final String insumo;
  final String unidad;
  final double requerido;
  final double disponible;
  final double consumido;
  final double faltante;
  final double costoUnitario;

  double get costoFaltante => faltante * costoUnitario;
}

class ReportRepository {
  Future<ResumenFinanciero> getResumen(DateTime desde, DateTime hasta) async {
    final db = await AppDatabase.instance.database;
    final inicio = sqlDateTime(desde);
    final fin = sqlDateTime(hasta);
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE((SELECT SUM(total) FROM pedidos
                  WHERE estado_pago <> 'ANULADO' AND estado_entrega <> 'ANULADO'
                    AND fecha >= ? AND fecha < ?), 0) AS ventas,
        COALESCE((SELECT COUNT(*) FROM pedidos
                  WHERE estado_pago <> 'ANULADO' AND estado_entrega <> 'ANULADO'
                    AND fecha >= ? AND fecha < ?), 0) AS pedidos,
        COALESCE((SELECT SUM(monto) FROM pagos
                  WHERE estado = 'CONFIRMADO' AND metodo_pago = 'EFECTIVO'
                    AND fecha >= ? AND fecha < ?), 0) AS cobros_efectivo,
        COALESCE((SELECT SUM(monto) FROM pagos
                  WHERE estado = 'CONFIRMADO' AND metodo_pago = 'QR'
                    AND fecha >= ? AND fecha < ?), 0) AS cobros_qr,
        COALESCE((SELECT SUM(a.cantidad * i.costo_promedio)
                  FROM ajustes_stock a
                  INNER JOIN insumos i ON i.id = a.insumo_id
                  WHERE a.cantidad > 0
                    AND a.fecha >= ? AND a.fecha < ?), 0) AS gasto_insumos,
        COALESCE((SELECT SUM(monto) FROM gastos
                  WHERE estado = 'REGISTRADO'
                    AND fecha >= ? AND fecha < ?), 0) AS salidas,
        COALESCE((SELECT SUM(monto) FROM gastos
                  WHERE estado = 'REGISTRADO' AND metodo_pago = 'EFECTIVO'
                    AND fecha >= ? AND fecha < ?), 0) AS salidas_efectivo,
        COALESCE((SELECT SUM(monto) FROM gastos
                  WHERE estado = 'REGISTRADO' AND metodo_pago = 'QR'
                    AND fecha >= ? AND fecha < ?), 0) AS salidas_qr
    ''',
      [
        inicio, fin, // ventas
        inicio, fin, // pedidos
        inicio, fin, // cobros efectivo
        inicio, fin, // cobros qr
        inicio, fin, // gasto en insumos
        inicio, fin, // salidas
        inicio, fin, // salidas efectivo
        inicio, fin, // salidas qr
      ],
    );
    final row = rows.first;
    double value(String key) => (row[key] as num?)?.toDouble() ?? 0;
    return ResumenFinanciero(
      ventas: value('ventas'),
      pedidos: value('pedidos').toInt(),
      cobrosEfectivo: value('cobros_efectivo'),
      cobrosQr: value('cobros_qr'),
      gastoInsumos: value('gasto_insumos'),
      salidas: value('salidas'),
      salidasEfectivo: value('salidas_efectivo'),
      salidasQr: value('salidas_qr'),
    );
  }

  Future<List<ProductoReporte>> getProductos(
    DateTime desde,
    DateTime hasta,
  ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT dp.nombre_producto AS nombre,
             SUM(dp.cantidad) AS cantidad,
             SUM(dp.subtotal) AS ventas,
             SUM(
               COALESCE(NULLIF(dp.costo_unitario, 0), COALESCE(pr.costo_unitario, 0))
               * dp.cantidad
             ) AS costo,
             CASE WHEN SUM(dp.cantidad) > 0
                  THEN SUM(dp.subtotal) / SUM(dp.cantidad) ELSE 0 END AS precio_unitario,
             COALESCE(c.color, 4280391418) AS categoria_color
      FROM detalle_pedido dp
      INNER JOIN pedidos p ON p.id = dp.pedido_id
      LEFT JOIN productos pr ON pr.id = dp.producto_id
      LEFT JOIN categorias_producto c ON c.id = pr.categoria_id
      WHERE p.estado_pago <> 'ANULADO'
        AND p.estado_entrega <> 'ANULADO'
        AND dp.es_componente = 0
        AND p.fecha >= ? AND p.fecha < ?
      GROUP BY dp.nombre_producto, c.color
      ORDER BY ventas DESC
    ''',
      [sqlDateTime(desde), sqlDateTime(hasta)],
    );
    return rows
        .map(
          (row) => ProductoReporte(
            nombre: row['nombre']! as String,
            cantidad: (row['cantidad'] as num).toDouble(),
            ventas: (row['ventas'] as num).toDouble(),
            costo: (row['costo'] as num).toDouble(),
            color: (row['categoria_color'] as num).toInt(),
            precioUnitario: (row['precio_unitario'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  Future<List<PedidoReporte>> getPedidos(DateTime desde, DateTime hasta) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT p.id, p.fecha, p.referencia, p.total, p.estado_pago,
             p.estado_entrega, u.nombre AS usuario,
             COALESCE(c.numero_turno, 0) AS numero_turno,
             COALESCE(SUM(CASE
               WHEN pg.estado = 'CONFIRMADO' AND pg.metodo_pago = 'EFECTIVO'
               THEN pg.monto ELSE 0 END), 0) AS efectivo,
             COALESCE(SUM(CASE
               WHEN pg.estado = 'CONFIRMADO' AND pg.metodo_pago = 'QR'
               THEN pg.monto ELSE 0 END), 0) AS qr
      FROM pedidos p
      INNER JOIN usuarios u ON u.id = p.usuario_id
      LEFT JOIN cajas c ON c.id = p.caja_id
      LEFT JOIN pagos pg ON pg.pedido_id = p.id
      WHERE p.fecha >= ? AND p.fecha < ?
        AND p.estado_pago <> 'ANULADO'
        AND p.estado_entrega <> 'ANULADO'
      GROUP BY p.id
      ORDER BY p.fecha DESC
    ''',
      [sqlDateTime(desde), sqlDateTime(hasta)],
    );
    return rows
        .map(
          (row) => PedidoReporte(
            id: row['id']! as int,
            fecha: row['fecha']! as String,
            referencia: row['referencia'] as String?,
            usuario: (row['usuario'] as String?) ?? '',
            numeroTurno: ((row['numero_turno'] as num?) ?? 0).toInt(),
            total: (row['total'] as num).toDouble(),
            efectivo: (row['efectivo'] as num).toDouble(),
            qr: (row['qr'] as num).toDouble(),
            estadoPago: row['estado_pago']! as String,
            estadoEntrega: row['estado_entrega']! as String,
          ),
        )
        .toList();
  }

  Future<List<GastoReporte>> getSalidasPorMotivo(
    DateTime desde,
    DateTime hasta,
  ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(NULLIF(g.descripcion, ''), cg.nombre) AS nombre,
             SUM(g.monto) AS total
      FROM gastos g
      INNER JOIN categorias_gasto cg ON cg.id = g.categoria_gasto_id
      WHERE g.estado = 'REGISTRADO' AND g.fecha >= ? AND g.fecha < ?
      GROUP BY COALESCE(NULLIF(g.descripcion, ''), cg.nombre)
      ORDER BY total DESC
    ''',
      [sqlDateTime(desde), sqlDateTime(hasta)],
    );
    return rows
        .map(
          (row) => GastoReporte(
            nombre: row['nombre']! as String,
            total: (row['total'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<List<SalidaReporte>> getSalidasDetalladas(
    DateTime desde,
    DateTime hasta,
  ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT g.fecha, g.monto, g.metodo_pago,
             COALESCE(NULLIF(g.descripcion, ''), cg.nombre) AS detalle,
             u.nombre AS usuario,
             COALESCE(c.numero_turno, 0) AS numero_turno
      FROM gastos g
      INNER JOIN categorias_gasto cg ON cg.id = g.categoria_gasto_id
      INNER JOIN usuarios u ON u.id = g.usuario_id
      LEFT JOIN cajas c ON c.id = g.caja_id
      WHERE g.estado = 'REGISTRADO' AND g.fecha >= ? AND g.fecha < ?
      ORDER BY g.fecha DESC, g.id DESC
    ''',
      [sqlDateTime(desde), sqlDateTime(hasta)],
    );
    return rows
        .map(
          (row) => SalidaReporte(
            fecha:
                DateTime.tryParse(row['fecha']! as String) ?? DateTime.now(),
            detalle: row['detalle']! as String,
            metodoPago: row['metodo_pago']! as String,
            monto: (row['monto'] as num).toDouble(),
            usuario: (row['usuario'] as String?) ?? '',
            turno: ((row['numero_turno'] as num?) ?? 0).toInt(),
          ),
        )
        .toList();
  }

  Future<List<InventarioReporte>> getInventario() async {
    final db = await AppDatabase.instance.database;
    final insumos = await db.rawQuery('''
      SELECT i.nombre, i.modo_control, i.stock_minimo, i.costo_promedio,
             COALESCE(s.stock, 0) AS stock
      FROM insumos i
      LEFT JOIN v_stock_insumos s ON s.insumo_id = i.id
      WHERE i.activo = 1
      ORDER BY i.nombre COLLATE NOCASE
    ''');
    final productos = await db.rawQuery('''
      SELECT p.nombre, p.stock_minimo, p.costo_unitario,
             COALESCE(s.stock, 0) AS stock
      FROM productos p
      LEFT JOIN v_stock_productos s ON s.producto_id = p.id
      WHERE p.activo = 1 AND p.tipo = 'DIRECTO'
      ORDER BY p.nombre COLLATE NOCASE
    ''');
    final items = <InventarioReporte>[];
    for (final row in insumos) {
      final modo = row['modo_control'] as String?;
      final stock = (row['stock'] as num).toDouble();
      final minimo = (row['stock_minimo'] as num).toDouble();
      items.add(
        InventarioReporte(
          nombre: row['nombre']! as String,
          tipo: 'INSUMO',
          modoControl: modo,
          stock: stock,
          stockMinimo: minimo,
          costoUnitario: (row['costo_promedio'] as num).toDouble(),
          alerta: modo != 'DISPONIBILIDAD' && stock <= minimo,
        ),
      );
    }
    for (final row in productos) {
      final stock = (row['stock'] as num).toDouble();
      final minimo = (row['stock_minimo'] as num).toDouble();
      items.add(
        InventarioReporte(
          nombre: row['nombre']! as String,
          tipo: 'PRODUCTO',
          modoControl: null,
          stock: stock,
          stockMinimo: minimo,
          costoUnitario: (row['costo_unitario'] as num).toDouble(),
          alerta: stock <= minimo,
        ),
      );
    }
    return items;
  }

  Future<List<InventarioReporte>> getAlertasStock() async {
    final inventario = await getInventario();
    return inventario.where((item) => item.alerta).toList();
  }

  Future<List<FaltanteInsumoReporte>> getFaltantes(
    DateTime desde,
    DateTime hasta,
  ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT f.fecha, pe.referencia, p.nombre AS producto,
             i.nombre AS insumo, u.abreviatura AS unidad,
             f.cantidad_requerida, f.cantidad_disponible,
             f.cantidad_consumida, f.cantidad_faltante, f.costo_unitario
      FROM faltantes_insumo f
      INNER JOIN productos p ON p.id = f.producto_id
      INNER JOIN insumos i ON i.id = f.insumo_id
      INNER JOIN unidades_medida u ON u.id = i.unidad_id
      LEFT JOIN pedidos pe ON pe.id = f.pedido_id
      WHERE f.estado = 'CONFIRMADO'
        AND f.fecha >= ? AND f.fecha < ?
      ORDER BY f.fecha DESC, f.id DESC
    ''',
      [sqlDateTime(desde), sqlDateTime(hasta)],
    );
    return rows
        .map(
          (row) => FaltanteInsumoReporte(
            fecha:
                DateTime.tryParse(row['fecha']! as String) ?? DateTime.now(),
            referencia: row['referencia'] as String?,
            producto: row['producto']! as String,
            insumo: row['insumo']! as String,
            unidad: row['unidad']! as String,
            requerido: (row['cantidad_requerida'] as num).toDouble(),
            disponible: (row['cantidad_disponible'] as num).toDouble(),
            consumido: (row['cantidad_consumida'] as num).toDouble(),
            faltante: (row['cantidad_faltante'] as num).toDouble(),
            costoUnitario: (row['costo_unitario'] as num).toDouble(),
          ),
        )
        .toList();
  }
}
