import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'date_utils.dart';
import 'report_repository.dart';

class ReportExportData {
  const ReportExportData({
    required this.desde,
    required this.hasta,
    required this.resumen,
    required this.productos,
    required this.salidas,
    required this.pedidos,
    this.faltantes = const [],
    this.negocio = 'Conwich',
  });

  final DateTime desde;
  final DateTime hasta;
  final ResumenFinanciero resumen;
  final List<ProductoReporte> productos;
  final List<SalidaReporte> salidas;
  final List<PedidoReporte> pedidos;
  final List<FaltanteInsumoReporte> faltantes;
  final String negocio;

  DateTime get finMostrar => hasta.subtract(const Duration(seconds: 1));
}

class ReportExporter {
  static const _pdfMime = 'application/pdf';
  static const _excelMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  String nombreArchivo(ReportExportData data, {required String extension}) {
    String dos(int value) => value.toString().padLeft(2, '0');
    final desde =
        '${data.desde.year}-${dos(data.desde.month)}-${dos(data.desde.day)}';
    final hasta =
        '${data.hasta.year}-${dos(data.hasta.month)}-${dos(data.hasta.day)}';
    return 'conwich_reporte_${desde}_$hasta.$extension';
  }

  Future<Uint8List> generarPdf(ReportExportData data) async {
    final doc = pw.Document();
    final productos = [...data.productos]
      ..sort((a, b) => b.ventas.compareTo(a.ventas));
    final top = productos.take(10).toList();
    final resumen = data.resumen;
    final scheme = PdfColor.fromHex('#0F766E');
    final suave = PdfColor.fromHex('#E6F2F0');
    final gris = PdfColor.fromHex('#5F6B6A');

    pw.Widget dato(String etiqueta, String valor) => pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: suave,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            etiqueta.toUpperCase(),
            style: pw.TextStyle(fontSize: 7, color: gris, letterSpacing: 0.6),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            valor,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );

    pw.Widget barra(ProductoReporte producto, double maximo) {
      final proporcion = maximo <= 0 ? 0.0 : producto.ventas / maximo;
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Row(
          children: [
            pw.SizedBox(
              width: 150,
              child: pw.Text(
                producto.nombre,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pw.SizedBox(width: 6),
            pw.SizedBox(
              width: 250,
              child: pw.Row(
                children: [
                  pw.Container(
                    width: 250 * proporcion,
                    height: 9,
                    decoration: pw.BoxDecoration(
                      color: scheme,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              formatMoney(producto.ventas),
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(width: 6),
            pw.Text(
              '(${_qty(producto.cantidad)})',
              style: pw.TextStyle(fontSize: 8, color: gris),
            ),
          ],
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    data.negocio,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: scheme,
                    ),
                  ),
                ),
                pw.Text(
                  'REPORTE DE VENTAS',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: gris,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${formatDateShort(data.desde)} al ${formatDateShort(data.finMostrar)} · '
              'Generado ${formatDateTimeShort(DateTime.now())}',
              style: pw.TextStyle(fontSize: 9, color: gris),
            ),
            pw.Divider(color: suave, thickness: 2),
          ],
        ),
        build: (context) => [
          pw.Text(
            'Resumen',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: scheme,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(child: dato('Ventas', formatMoney(resumen.ventas))),
              pw.SizedBox(width: 8),
              pw.Expanded(child: dato('Pedidos', '${resumen.pedidos}')),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: dato('Ticket promedio', formatMoney(resumen.ticketPromedio)),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(
                child: dato('Cobros en efectivo', formatMoney(resumen.cobrosEfectivo)),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(child: dato('Cobros QR', formatMoney(resumen.cobrosQr))),
              pw.SizedBox(width: 8),
              pw.Expanded(child: dato('Ganancia', formatMoney(resumen.ganancia))),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Productos más vendidos',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: scheme,
            ),
          ),
          pw.SizedBox(height: 8),
          if (top.isEmpty)
            pw.Text('Sin ventas en el período.', style: const pw.TextStyle(fontSize: 9))
          else
            ...top.map(
              (producto) => barra(
                producto,
                top.first.ventas <= 0 ? 1 : top.first.ventas,
              ),
            ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Productos vendidos',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: scheme,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Producto',
              'Cantidad',
              'Precio unit.',
              'Ventas',
              'Costo',
              'Ganancia',
            ],
            data: productos
                .map(
                  (producto) => [
                    producto.nombre,
                    _qty(producto.cantidad),
                    formatMoney(producto.precioUnitario),
                    formatMoney(producto.ventas),
                    formatMoney(producto.costo),
                    formatMoney(producto.ganancia),
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: pw.BoxDecoration(color: scheme),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Salidas de caja',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: scheme,
            ),
          ),
          pw.SizedBox(height: 8),
          if (data.salidas.isEmpty)
            pw.Text('Sin salidas registradas.', style: const pw.TextStyle(fontSize: 9))
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Fecha', 'Detalle', 'Método', 'Cajero', 'Turno', 'Monto'],
              data: data.salidas
                  .map(
                    (salida) => [
                      formatDateTimeShort(salida.fecha),
                      salida.detalle,
                      salida.metodoPago,
                      salida.usuario,
                      salida.turnoLabel,
                      formatMoney(salida.monto),
                    ],
                  )
                  .toList(),
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: scheme),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignments: {5: pw.Alignment.centerRight},
            ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Pedidos',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: scheme,
            ),
          ),
          pw.SizedBox(height: 8),
          if (data.pedidos.isEmpty)
            pw.Text('Sin pedidos en el período.', style: const pw.TextStyle(fontSize: 9))
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Pedido',
                'Fecha',
                'Cajero',
                'Turno',
                'Total',
                'Efectivo',
                'QR',
                'Estado',
              ],
              data: data.pedidos
                  .map(
                    (pedido) => [
                      pedido.referencia == null
                          ? '#${pedido.id}'
                          : '${pedido.referencia} · #${pedido.id}',
                      _fechaHora(pedido.fecha),
                      pedido.usuario,
                      pedido.turnoLabel,
                      formatMoney(pedido.total),
                      formatMoney(pedido.efectivo),
                      formatMoney(pedido.qr),
                      pedido.estadoPago,
                    ],
                  )
                  .toList(),
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: scheme),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignments: {
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
              },
            ),
          if (data.faltantes.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text(
              'Faltantes de insumo',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: scheme,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Fecha',
                'Pedido',
                'Producto',
                'Insumo',
                'Faltante',
                'Costo',
              ],
              data: data.faltantes
                  .map(
                    (item) => [
                      formatDateTimeShort(item.fecha),
                      item.referencia ?? '—',
                      item.producto,
                      item.insumo,
                      '${_qty(item.faltante)} ${item.unidad}',
                      formatMoney(item.costoFaltante),
                    ],
                  )
                  .toList(),
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: scheme),
              cellStyle: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }

  Future<Uint8List> generarExcel(ReportExportData data) async {
    final excel = Excel.createExcel();
    final porDefecto = excel.getDefaultSheet();
    if (porDefecto != null && porDefecto != 'Resumen') {
      excel.delete(porDefecto);
    }
    final resumen = excel['Resumen'];
    void fila(String etiqueta, Object? valor) {
      resumen.appendRow([TextCellValue(etiqueta), _celda(valor)]);
    }

    resumen.appendRow([TextCellValue('REPORTE DE VENTAS')]);
    fila('Negocio', data.negocio);
    fila('Desde', formatDateShort(data.desde));
    fila('Hasta', formatDateShort(data.finMostrar));
    fila('Generado', formatDateTimeShort(DateTime.now()));
    resumen.appendRow([TextCellValue('')]);
    final r = data.resumen;
    fila('Ventas', r.ventas);
    fila('Pedidos', r.pedidos);
    fila('Ticket promedio', r.ticketPromedio);
    fila('Cobros en efectivo', r.cobrosEfectivo);
    fila('Cobros QR', r.cobrosQr);
    fila('Gasto en insumos', r.gastoInsumos);
    fila('Salidas de caja', r.salidas);
    fila('Ganancia', r.ganancia);

    final productos = excel['Productos'];
    productos.appendRow([
      TextCellValue('Producto'),
      TextCellValue('Cantidad'),
      TextCellValue('Precio unitario'),
      TextCellValue('Ventas'),
      TextCellValue('Costo'),
      TextCellValue('Ganancia'),
    ]);
    for (final producto in data.productos) {
      productos.appendRow([
        TextCellValue(producto.nombre),
        DoubleCellValue(producto.cantidad),
        DoubleCellValue(producto.precioUnitario),
        DoubleCellValue(producto.ventas),
        DoubleCellValue(producto.costo),
        DoubleCellValue(producto.ganancia),
      ]);
    }
    for (var i = 0; i < 6; i++) {
      productos.setColumnWidth(i, 22);
    }

    final salidas = excel['Salidas'];
    salidas.appendRow([
      TextCellValue('Fecha'),
      TextCellValue('Detalle'),
      TextCellValue('Método'),
      TextCellValue('Cajero'),
      TextCellValue('Turno'),
      TextCellValue('Monto'),
    ]);
    for (final salida in data.salidas) {
      salidas.appendRow([
        TextCellValue(formatDateTimeShort(salida.fecha)),
        TextCellValue(salida.detalle),
        TextCellValue(salida.metodoPago),
        TextCellValue(salida.usuario),
        TextCellValue(salida.turnoLabel),
        DoubleCellValue(salida.monto),
      ]);
    }
    for (var i = 0; i < 6; i++) {
      salidas.setColumnWidth(i, 22);
    }

    final pedidos = excel['Pedidos'];
    pedidos.appendRow([
      TextCellValue('Pedido'),
      TextCellValue('Fecha'),
      TextCellValue('Cajero'),
      TextCellValue('Turno'),
      TextCellValue('Total'),
      TextCellValue('Efectivo'),
      TextCellValue('QR'),
      TextCellValue('Estado'),
    ]);
    for (final pedido in data.pedidos) {
      pedidos.appendRow([
        TextCellValue(
          pedido.referencia == null
              ? '#${pedido.id}'
              : '${pedido.referencia} · #${pedido.id}',
        ),
        TextCellValue(_fechaHora(pedido.fecha)),
        TextCellValue(pedido.usuario),
        TextCellValue(pedido.turnoLabel),
        DoubleCellValue(pedido.total),
        DoubleCellValue(pedido.efectivo),
        DoubleCellValue(pedido.qr),
        TextCellValue(pedido.estadoPago),
      ]);
    }
    for (var i = 0; i < 8; i++) {
      pedidos.setColumnWidth(i, 20);
    }

    final grafico = excel['Gráfico'];
    grafico.appendRow([
      TextCellValue('Producto'),
      TextCellValue('Ventas'),
      TextCellValue('Cantidad'),
      TextCellValue(''),
    ]);
    final top = [...data.productos]
      ..sort((a, b) => b.ventas.compareTo(a.ventas));
    final maximo = top.isEmpty ? 1.0 : top.first.ventas;
    final estiloBarra = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('FF0F766E'),
    );
    for (final producto in top.take(10)) {
      final fila = grafico.maxRows;
      final bloques = maximo <= 0
          ? 0
          : ((producto.ventas / maximo) * 20).round();
      grafico.appendRow([
        TextCellValue(producto.nombre),
        DoubleCellValue(producto.ventas),
        DoubleCellValue(producto.cantidad),
        TextCellValue(''),
      ]);
      for (var i = 0; i < bloques; i++) {
        grafico.updateCell(
          CellIndex.indexByColumnRow(columnIndex: 3 + i, rowIndex: fila),
          TextCellValue(' '),
          cellStyle: estiloBarra,
        );
      }
    }
    grafico.setColumnWidth(0, 28);
    grafico.setColumnWidth(1, 14);
    grafico.setColumnWidth(2, 12);

    final faltantes = excel['Faltantes'];
    faltantes.appendRow([
      TextCellValue('Fecha'),
      TextCellValue('Pedido'),
      TextCellValue('Producto'),
      TextCellValue('Insumo'),
      TextCellValue('Faltante'),
      TextCellValue('Costo'),
    ]);
    for (final item in data.faltantes) {
      faltantes.appendRow([
        TextCellValue(formatDateTimeShort(item.fecha)),
        TextCellValue(item.referencia ?? '—'),
        TextCellValue(item.producto),
        TextCellValue(item.insumo),
        TextCellValue('${_qty(item.faltante)} ${item.unidad}'),
        DoubleCellValue(item.costoFaltante),
      ]);
    }

    final bytes = excel.save();
    if (bytes == null) {
      throw StateError('No se pudo generar el archivo de Excel.');
    }
    return Uint8List.fromList(bytes);
  }

  Future<void> compartirPdf(
    Uint8List bytes, {
    required String nombre,
    Rect? origen,
  }) async {
    await Printing.sharePdf(bytes: bytes, filename: nombre);
  }

  Future<bool> guardarPdf(Uint8List bytes, {required String nombre}) async {
    final uri = await FilePicker.saveFile(
      fileName: nombre,
      bytes: bytes,
      mimeType: _pdfMime,
      dialogTitle: 'Guardar reporte PDF',
    );
    return uri != null;
  }

  Future<void> compartirExcel(
    Uint8List bytes, {
    required String nombre,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: _excelMime, name: nombre)],
        fileNameOverrides: [nombre],
        title: 'Reporte de Conwich',
        subject: 'Reporte de Conwich',
      ),
    );
  }

  Future<bool> guardarExcel(Uint8List bytes, {required String nombre}) async {
    final uri = await FilePicker.saveFile(
      fileName: nombre,
      bytes: bytes,
      mimeType: _excelMime,
      dialogTitle: 'Guardar reporte Excel',
    );
    return uri != null;
  }

  CellValue? _celda(Object? valor) {
    if (valor == null) return TextCellValue('');
    if (valor is bool) return BoolCellValue(valor);
    if (valor is int) return IntCellValue(valor);
    if (valor is double) return DoubleCellValue(valor);
    if (valor is num) return DoubleCellValue(valor.toDouble());
    return TextCellValue(valor.toString());
  }

  String _qty(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  String _fechaHora(String value) {
    final fecha = parseSqlDateTime(value);
    return fecha == null ? value : formatDateTimeShort(fecha);
  }
}
