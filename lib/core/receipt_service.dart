import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/database/app_database.dart';
import 'date_utils.dart';
import 'sales_repository.dart';

/// Genera la nota de venta en un PDF de 80 mm y la envía al diálogo de
/// impresión del sistema (útil para impresoras térmicas).
class ReceiptService {
  Future<Uint8List> generarNotaVenta({
    required PedidoDetalle detalle,
    required String turno,
    required String cajero,
  }) async {
    final meta = await AppDatabase.instance.leerAppMeta();
    final negocio = (meta?['nombre_negocio'] as String?) ?? 'Conwich';
    final pedido = detalle.pedido;
    final fecha = parseSqlDateTime(pedido.fecha);
    final fechaTexto = fecha == null
        ? pedido.fecha
        : formatDateTimeShort(fecha);

    double sumar(String metodo) => detalle.pagos
        .where((pago) => pago.metodo == metodo && pago.estado == 'CONFIRMADO')
        .fold<double>(0, (suma, pago) => suma + pago.monto);
    final efectivo = sumar('EFECTIVO');
    final qr = sumar('QR');

    final doc = pw.Document();
    final pequeno = pw.TextStyle(fontSize: 8);
    final negrita = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);

    pw.Widget fila(String etiqueta, String valor) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 1.5),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(etiqueta, style: pequeno)),
          pw.Text(valor, style: pequeno),
        ],
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: const PdfPageFormat(
          80 * PdfPageFormat.mm,
          297 * PdfPageFormat.mm,
          marginAll: 4 * PdfPageFormat.mm,
        ),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              negocio,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Center(
            child: pw.Text(
              'NOTA DE VENTA',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Divider(),
          fila('Pedido', '#${pedido.id}'),
          fila('Fecha', fechaTexto),
          if (turno.isNotEmpty) fila('Turno', turno),
          fila('Cajero', cajero),
          if (pedido.referencia != null) fila('Referencia', pedido.referencia!),
          pw.Divider(),
          ...detalle.lineas.map(
            (linea) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '${_cantidad(linea.cantidad)} x ${linea.nombre}',
                      style: pequeno,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Text(formatMoney(linea.subtotal), style: pequeno),
                ],
              ),
            ),
          ),
          pw.Divider(),
          fila('TOTAL', formatMoney(pedido.total)),
          pw.SizedBox(height: 3),
          if (efectivo > 0) fila('Efectivo', formatMoney(efectivo)),
          if (qr > 0) fila('QR', formatMoney(qr)),
          pw.Divider(),
          pw.Center(child: pw.Text('Gracias por su compra', style: negrita)),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> imprimirNotaVenta({
    required PedidoDetalle detalle,
    required String turno,
    required String cajero,
  }) async {
    final bytes = await generarNotaVenta(
      detalle: detalle,
      turno: turno,
      cajero: cajero,
    );
    await Printing.layoutPdf(
      name: 'nota_venta_${detalle.pedido.id}.pdf',
      onLayout: (_) async => bytes,
    );
  }

  String _cantidad(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }
}
