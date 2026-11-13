import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:test_code_02/core/report_exporter.dart';
import 'package:test_code_02/core/report_repository.dart';

void main() {
  ReportExportData datos() => ReportExportData(
    desde: DateTime(2026, 11, 13),
    hasta: DateTime(2026, 11, 14),
    resumen: const ResumenFinanciero(
      ventas: 120,
      cobrosEfectivo: 80,
      cobrosQr: 40,
      gastoInsumos: 30,
      salidas: 10,
      salidasEfectivo: 6,
      salidasQr: 4,
      pedidos: 4,
    ),
    productos: const [
      ProductoReporte(
        nombre: 'Almuerzo armado',
        cantidad: 3,
        ventas: 60,
        costo: 20,
        color: 0xFF0F766E,
        precioUnitario: 20,
      ),
      ProductoReporte(
        nombre: 'Refresco',
        cantidad: 6,
        ventas: 60,
        costo: 18,
        color: 0xFF16A34A,
        precioUnitario: 10,
      ),
    ],
    salidas: [
      SalidaReporte(
        fecha: DateTime(2026, 11, 13, 10, 30),
        detalle: 'Gas para la cocina',
        metodoPago: 'EFECTIVO',
        monto: 10,
        usuario: 'Administrador',
        turno: 1,
      ),
    ],
    pedidos: [
      PedidoReporte(
        id: 1,
        fecha: '2026-11-13 12:00:00',
        referencia: 'Mesa 2',
        usuario: 'Administrador',
        numeroTurno: 1,
        total: 40,
        efectivo: 30,
        qr: 10,
        estadoPago: 'PAGADO',
        estadoEntrega: 'ENTREGADO',
      ),
    ],
  );

  test('genera un PDF carta con el resumen y el gráfico', () async {
    final bytes = await ReportExporter().generarPdf(datos());
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('genera un Excel con las hojas del reporte y el gráfico', () async {
    final bytes = await ReportExporter().generarExcel(datos());
    expect(bytes.sublist(0, 2), [0x50, 0x4B]);
    final libro = Excel.decodeBytes(bytes);
    expect(libro.tables.containsKey('Resumen'), isTrue);
    expect(libro.tables.containsKey('Productos'), isTrue);
    expect(libro.tables.containsKey('Salidas'), isTrue);
    expect(libro.tables.containsKey('Pedidos'), isTrue);
    expect(libro.tables.containsKey('Gráfico'), isTrue);
    final resumen = libro.tables['Resumen']!.rows
        .map((fila) => fila.map((celda) => celda?.value.toString()).toList())
        .toList();
    final filaVentas = resumen.firstWhere((fila) => fila.first == 'Ventas');
    expect(double.tryParse(filaVentas[1] ?? ''), 120);
    final productos = libro.tables['Productos']!;
    expect(
      productos.rows.first.map((celda) => celda?.value.toString()).toList(),
      contains('Precio unitario'),
    );
  });
}
