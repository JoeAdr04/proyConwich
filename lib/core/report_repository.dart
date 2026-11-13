import '../data/database/app_database.dart';
import 'date_utils.dart';

class ResumenFinanciero {
  const ResumenFinanciero({
    required this.ventas,
    required this.cobrosEfectivo,
    required this.cobrosQr,
    required this.cogs,
    required this.salidas,
    required this.salidasEfectivo,
    required this.salidasQr,
    required this.pedidos,
  });

  final double ventas;
  final double cobrosEfectivo;
  final double cobrosQr;
  final double cogs;
  final double salidas;
  final double salidasEfectivo;
  final double salidasQr;
  final int pedidos;

  double get cobros => cobrosEfectivo + cobrosQr;
  double get resultado => ventas - cogs - salidas;
  double get flujoCaja => cobros - salidas;
  double get ticketPromedio => pedidos == 0 ? 0 : ventas / pedidos;
  double get margenBruto => ventas == 0 ? 0 : (ventas - cogs) / ventas;
}

class ProductoReporte {
  const ProductoReporte({
    required this.nombre,
    required this.cantidad,
    required this.ventas,
    required this.cogs,
  });

  final String nombre;
  final double cantidad;
  final double ventas;
  final double cogs;

  double get margen => ventas - cogs;
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
        COALESCE((SELECT SUM(ci.costo_unitario * ci.cantidad)
                  FROM consumos_insumo ci
                  WHERE ci.estado = 'CONFIRMADO'
                    AND ci.fecha >= ? AND ci.fecha < ?), 0)
        + COALESCE((SELECT SUM(dp.costo_unitario * dp.cantidad)
                    FROM detalle_pedido dp
                    INNER JOIN pedidos p ON p.id = dp.pedido_id
                    WHERE dp.costo_unitario > 0
                      AND p.estado_pago <> 'ANULADO'
                      AND p.estado_entrega <> 'ANULADO'
                      AND p.fecha >= ? AND p.fecha < ?), 0) AS cogs,
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
        inicio, fin, // cogs consumos
        inicio, fin, // cogs productos directos
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
      cogs: value('cogs'),
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
               CASE WHEN dp.costo_unitario > 0
                 THEN dp.costo_unitario * dp.cantidad
                 ELSE COALESCE((
                   SELECT SUM(ci.costo_unitario * ci.cantidad)
                   FROM consumos_insumo ci
                   WHERE ci.detalle_pedido_id = dp.id
                     AND ci.estado = 'CONFIRMADO'
                 ), 0)
               END
             ) AS cogs
      FROM detalle_pedido dp
      INNER JOIN pedidos p ON p.id = dp.pedido_id
      WHERE p.estado_pago <> 'ANULADO'
        AND p.estado_entrega <> 'ANULADO'
        AND p.fecha >= ? AND p.fecha < ?
      GROUP BY dp.nombre_producto
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
            cogs: (row['cogs'] as num).toDouble(),
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
