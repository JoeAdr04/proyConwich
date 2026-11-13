import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/database/app_database.dart';
import '../app_info.dart';
import '../date_utils.dart';

/// Exporta los datos a un único `.xlsx` con una hoja por tabla.
///
/// Es una copia legible para revisar o llevar a contabilidad; **no** sirve
/// para restaurar la aplicación (para eso está el respaldo `.db`).
class ExcelExporter {
  static const _mime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// Tablas exportadas con su nombre amigable. Se excluyen `sesion_actual`
  /// (estado interno), `app_meta` (va en el resumen) y los datos sensibles.
  static const _tablas = <String, String>{
    'categorias_producto': 'Categorías de producto',
    'unidades_medida': 'Unidades de medida',
    'productos': 'Productos',
    'insumos': 'Insumos',
    'receta_insumos': 'Recetas',
    'menus_dia': 'Menús del día',
    'menu_dia_items': 'Ítems de menú',
    'cajas': 'Cajas',
    'pedidos': 'Pedidos',
    'detalle_pedido': 'Detalle de pedidos',
    'pagos': 'Pagos',
    'compras': 'Compras',
    'detalle_compra': 'Detalle de compras',
    'consumos_insumo': 'Consumos de insumo',
    'faltantes_insumo': 'Faltantes de insumo',
    'ajustes_stock': 'Ajustes de stock',
    'conteos_inventario': 'Conteos de inventario',
    'detalle_conteo': 'Detalle de conteos',
    'categorias_gasto': 'Categorías de gasto',
    'gastos': 'Gastos',
    'sueldos': 'Sueldos',
    'usuarios': 'Usuarios',
    'usuario_permisos': 'Permisos de usuario',
  };

  static const _columnasOcultas = <String, Set<String>>{
    'usuarios': {'password_hash'},
    'productos': {'imagen'},
  };

  String nombreArchivo(DateTime fecha) => 'sazon_datos_${_stamp(fecha)}.xlsx';

  Future<Uint8List> generar({DateTime? ahora}) async {
    final momento = ahora ?? DateTime.now();
    final db = await AppDatabase.instance.database;
    final meta = await AppDatabase.instance.leerAppMeta();
    final excel = Excel.createExcel();
    final porDefecto = excel.getDefaultSheet();

    final resumen = excel['Resumen'];
    if (porDefecto != null && porDefecto != 'Resumen') {
      excel.delete(porDefecto);
    }

    final conteos = <String, int>{};
    for (final entrada in _tablas.entries) {
      final total = await _agregarHoja(db, excel, entrada.key, entrada.value);
      conteos[entrada.value] = total;
    }

    void fila(String etiqueta, String valor) {
      resumen.appendRow([TextCellValue(etiqueta), TextCellValue(valor)]);
    }

    fila('Aplicación', appNombre);
    fila('Versión de la app', appVersionEtiqueta);
    fila('Instalación', '${meta?['instalacion_id'] ?? '—'}');
    fila('Último respaldo', '${meta?['ultimo_respaldo_en'] ?? '—'}');
    fila('Exportado el', sqlDateTime(momento));
    fila('Versión de esquema', '${AppDatabase.schemaVersion}');
    resumen.appendRow([TextCellValue('')]);
    resumen.appendRow([TextCellValue('Hoja'), TextCellValue('Registros')]);
    for (final entrada in conteos.entries) {
      resumen.appendRow([
        TextCellValue(entrada.key),
        IntCellValue(entrada.value),
      ]);
    }
    resumen.appendRow([TextCellValue('')]);
    resumen.appendRow([
      TextCellValue(
        'Nota: no se exportan las contraseñas ni las imágenes de productos. '
        'Este archivo es solo informativo y no permite restaurar la app.',
      ),
    ]);

    final bytes = excel.save();
    if (bytes == null) {
      throw StateError('No se pudo generar el archivo de Excel.');
    }
    return Uint8List.fromList(bytes);
  }

  Future<int> _agregarHoja(
    Database db,
    Excel excel,
    String tabla,
    String nombreHoja,
  ) async {
    final ocultas = _columnasOcultas[tabla] ?? const <String>{};
    final info = await db.rawQuery('PRAGMA table_info($tabla)');
    final columnas = info
        .map((c) => c['name'] as String)
        .where((c) => !ocultas.contains(c))
        .toList();
    final filas = await db.query(tabla);
    final hoja = excel[nombreHoja];
    hoja.appendRow(columnas.map<CellValue?>(TextCellValue.new).toList());
    for (final fila in filas) {
      hoja.appendRow(
        columnas.map<CellValue?>((columna) => _celda(fila[columna])).toList(),
      );
    }
    for (var i = 0; i < columnas.length; i++) {
      hoja.setColumnWidth(i, 22);
    }
    return filas.length;
  }

  CellValue? _celda(Object? valor) {
    if (valor == null) return TextCellValue('');
    if (valor is bool) return BoolCellValue(valor);
    if (valor is int) return IntCellValue(valor);
    if (valor is double) return DoubleCellValue(valor);
    if (valor is num) return DoubleCellValue(valor.toDouble());
    if (valor is Uint8List) return TextCellValue('[imagen adjunta]');
    if (valor is List<int>) return TextCellValue('[imagen adjunta]');
    return TextCellValue(valor.toString());
  }

  Future<void> compartir(
    Uint8List bytes, {
    required String nombre,
    Rect? origen,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: _mime, name: nombre)],
        fileNameOverrides: [nombre],
        title: 'Datos de Conwich',
        subject: 'Datos de Conwich',
        sharePositionOrigin: origen,
      ),
    );
  }

  Future<bool> guardar(Uint8List bytes, {required String nombre}) async {
    final uri = await FilePicker.saveFile(
      fileName: nombre,
      bytes: bytes,
      mimeType: _mime,
      dialogTitle: 'Guardar Excel',
    );
    return uri != null;
  }

  String _stamp(DateTime fecha) {
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${fecha.year}-${dos(fecha.month)}-${dos(fecha.day)}'
        '_${dos(fecha.hour)}-${dos(fecha.minute)}';
  }
}
