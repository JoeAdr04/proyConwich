import 'package:flutter/material.dart';

import '../../../core/date_utils.dart';
import '../../../core/receipt_service.dart';
import '../../../core/report_repository.dart';
import '../../../core/sales_repository.dart';
import '../../../ui/common.dart';

class _ReportData {
  const _ReportData({
    required this.resumen,
    required this.productos,
    required this.salidas,
    required this.inventario,
    required this.pedidos,
    required this.faltantes,
  });

  final ResumenFinanciero resumen;
  final List<ProductoReporte> productos;
  final List<GastoReporte> salidas;
  final List<InventarioReporte> inventario;
  final List<PedidoReporte> pedidos;
  final List<FaltanteInsumoReporte> faltantes;
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.refreshToken});

  final int refreshToken;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  static const _periodos = ['DIA', 'SEMANA', 'MES', 'TRIMESTRE', 'ANIO'];
  final _repository = ReportRepository();
  late Future<_ReportData> _future;
  String _periodo = 'DIA';
  DateTime _anchor = DateTime.now();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(ReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reload();
  }

  // Debe devolver void: si devolviera el Future, setState lanzaría error y la
  // pantalla no se refrescaría.
  void _reload() {
    _future = _load();
  }

  String _labelPeriodo(String value) => switch (value) {
    'DIA' => 'Día',
    'SEMANA' => 'Semana',
    'MES' => 'Mes',
    'TRIMESTRE' => 'Trimestre',
    _ => 'Año',
  };

  DateTimeRange get _range {
    final anchor = _anchor;
    switch (_periodo) {
      case 'SEMANA':
        final start = DateTime(
          anchor.year,
          anchor.month,
          anchor.day,
        ).subtract(Duration(days: anchor.weekday - 1));
        return DateTimeRange(
          start: start,
          end: start.add(const Duration(days: 7)),
        );
      case 'MES':
        return DateTimeRange(
          start: DateTime(anchor.year, anchor.month, 1),
          end: DateTime(anchor.year, anchor.month + 1, 1),
        );
      case 'TRIMESTRE':
        final startMonth = ((anchor.month - 1) ~/ 3) * 3 + 1;
        return DateTimeRange(
          start: DateTime(anchor.year, startMonth, 1),
          end: DateTime(anchor.year, startMonth + 3, 1),
        );
      case 'ANIO':
        return DateTimeRange(
          start: DateTime(anchor.year, 1, 1),
          end: DateTime(anchor.year + 1, 1, 1),
        );
      default:
        final start = DateTime(anchor.year, anchor.month, anchor.day);
        return DateTimeRange(
          start: start,
          end: start.add(const Duration(days: 1)),
        );
    }
  }

  void _mover(int delta) {
    setState(() {
      switch (_periodo) {
        case 'SEMANA':
          _anchor = _anchor.add(Duration(days: 7 * delta));
          break;
        case 'MES':
          _anchor = DateTime(_anchor.year, _anchor.month + delta, 1);
          break;
        case 'TRIMESTRE':
          _anchor = DateTime(_anchor.year, _anchor.month + 3 * delta, 1);
          break;
        case 'ANIO':
          _anchor = DateTime(_anchor.year + delta, 1, 1);
          break;
        default:
          _anchor = _anchor.add(Duration(days: delta));
      }
      _reload();
    });
  }

  Future<_ReportData> _load() async {
    final range = _range;
    final resumen = await _repository.getResumen(range.start, range.end);
    final productos = await _repository.getProductos(range.start, range.end);
    final salidas = await _repository.getSalidasPorMotivo(
      range.start,
      range.end,
    );
    final inventario = await _repository.getInventario();
    final pedidos = await _repository.getPedidos(range.start, range.end);
    final faltantes = await _repository.getFaltantes(range.start, range.end);
    return _ReportData(
      resumen: resumen,
      productos: productos,
      salidas: salidas,
      inventario: inventario,
      pedidos: pedidos,
      faltantes: faltantes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    final finMostrar = range.end.subtract(const Duration(days: 1));
    return DefaultTabController(
      length: 5,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
                12,
                esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeader(
                    title: 'Reportes',
                    subtitle: 'Resultado = ventas − costo de insumos − salidas. Flujo de caja = cobros − salidas.',
                    actions: [
                      OutlinedButton.icon(
                        onPressed: () => setState(_reload),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Actualizar'),
                      ),
                    ],
                  ),
                  AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ChoiceChipRow<String>(
                          values: _periodos,
                          labelBuilder: _labelPeriodo,
                          selected: _periodo,
                          onSelected: (value) => setState(() {
                            _periodo = value;
                            _anchor = DateTime.now();
                            _reload();
                          }),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          tooltip: 'Período anterior',
                          onPressed: () => _mover(-1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          '${formatDateShort(range.start)} — ${formatDateShort(finMostrar)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          tooltip: 'Período siguiente',
                          onPressed: () => _mover(1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarHeader(
              tabBar: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.summarize_outlined), text: 'Resumen'),
                  Tab(
                    icon: Icon(Icons.lunch_dining_outlined),
                    text: 'Productos',
                  ),
                  Tab(
                    icon: Icon(Icons.inventory_2_outlined),
                    text: 'Inventario',
                  ),
                  Tab(
                    icon: Icon(Icons.warning_amber_rounded),
                    text: 'Faltantes',
                  ),
                  Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Pedidos'),
                ],
              ),
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
        ],
        body: FutureBuilder<_ReportData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingView();
            }
            if (snapshot.hasError) {
              return ErrorView(
                message: '${snapshot.error}',
                onRetry: () => setState(_reload),
              );
            }
            final data = snapshot.data!;
            return TabBarView(
              children: [
                _resumenTab(context, data),
                _productosTab(context, data),
                _inventarioTab(context, data),
                _faltantesTab(context, data),
                _pedidosTab(context, data),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _resumenTab(BuildContext context, _ReportData data) {
    final resumen = data.resumen;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.all(
        esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
      ),
      children: [
        StatGrid(
          children: [
            StatCard(
              label: 'Ventas',
              value: formatMoney(resumen.ventas),
              caption: '${resumen.pedidos} pedidos',
              icon: Icons.trending_up,
            ),
            StatCard(
              label: 'Cobros',
              value: formatMoney(resumen.cobros),
              caption:
                  'Efectivo ${formatMoney(resumen.cobrosEfectivo)} · QR ${formatMoney(resumen.cobrosQr)}',
              icon: Icons.payments_outlined,
              color: scheme.tertiary,
            ),
            StatCard(
              label: 'COGS',
              value: formatMoney(resumen.cogs),
              caption: 'Costo de insumos vendidos',
              icon: Icons.soup_kitchen_outlined,
              color: scheme.secondary,
            ),
            StatCard(
              label: 'Salidas',
              value: formatMoney(resumen.salidas),
              caption:
                  'Efectivo ${formatMoney(resumen.salidasEfectivo)} · QR ${formatMoney(resumen.salidasQr)}',
              icon: Icons.outbox,
              color: scheme.tertiary,
            ),
            StatCard(
              label: 'Resultado',
              value: formatMoney(resumen.resultado),
              caption: 'Ventas − COGS − salidas',
              icon: Icons.insights,
              color: resumen.resultado >= 0 ? scheme.primary : scheme.error,
            ),
            StatCard(
              label: 'Flujo de caja',
              value: formatMoney(resumen.flujoCaja),
              caption: 'Cobros − salidas',
              icon: Icons.account_balance_outlined,
              color: resumen.flujoCaja >= 0 ? scheme.primary : scheme.error,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Indicadores',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              LabelValue(
                label: 'Ticket promedio',
                value: formatMoney(resumen.ticketPromedio),
              ),
              LabelValue(
                label: 'Margen bruto',
                value: formatPercent(resumen.margenBruto),
              ),
              LabelValue(
                label: 'Ventas en efectivo (cobros)',
                value: formatMoney(resumen.cobrosEfectivo),
              ),
              LabelValue(
                label: 'Ventas por QR (cobros)',
                value: formatMoney(resumen.cobrosQr),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Salidas registradas',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (data.salidas.isEmpty)
                const Text('No hay salidas registradas en el período.')
              else
                ...data.salidas.map(
                  (salida) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(salida.nombre)),
                        Text(
                          formatMoney(salida.total),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _productosTab(BuildContext context, _ReportData data) {
    if (data.productos.isEmpty) {
      return const EmptyState(
        icon: Icons.lunch_dining_outlined,
        title: 'Sin ventas en el período',
        message: 'No hay productos vendidos para mostrar.',
      );
    }
    return ListView(
      padding: EdgeInsets.all(
        esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
      ),
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Producto')),
                DataColumn(label: Text('Cantidad'), numeric: true),
                DataColumn(label: Text('Ventas'), numeric: true),
                DataColumn(label: Text('COGS'), numeric: true),
                DataColumn(label: Text('Margen'), numeric: true),
              ],
              rows: data.productos
                  .map(
                    (producto) => DataRow(
                      cells: [
                        DataCell(Text(producto.nombre)),
                        DataCell(Text(formatQty(producto.cantidad))),
                        DataCell(Text(formatMoney(producto.ventas))),
                        DataCell(Text(formatMoney(producto.cogs))),
                        DataCell(
                          Text(
                            formatMoney(producto.margen),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: producto.margen >= 0
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inventarioTab(BuildContext context, _ReportData data) {
    final total = data.inventario.fold<double>(
      0,
      (sum, item) => sum + item.valor,
    );
    final alertas = data.inventario.where((item) => item.alerta).length;
    return ListView(
      padding: EdgeInsets.all(
        esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
      ),
      children: [
        StatGrid(
          children: [
            StatCard(
              label: 'Valor del inventario',
              value: formatMoney(total),
              icon: Icons.inventory_2_outlined,
            ),
            StatCard(
              label: 'Ítems con alerta',
              value: '$alertas',
              icon: Icons.warning_amber_rounded,
              color: alertas == 0
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
            StatCard(
              label: 'Ítems controlados',
              value: '${data.inventario.length}',
              icon: Icons.list_alt_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (data.inventario.isEmpty)
          const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Sin inventario controlado',
            message:
                'Crea insumos o productos directos para ver su stock y valor.',
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Ítem')),
                  DataColumn(label: Text('Tipo')),
                  DataColumn(label: Text('Stock'), numeric: true),
                  DataColumn(label: Text('Mínimo'), numeric: true),
                  DataColumn(label: Text('Costo unit.'), numeric: true),
                  DataColumn(label: Text('Valor'), numeric: true),
                  DataColumn(label: Text('Alerta')),
                ],
                rows: data.inventario
                    .map(
                      (item) => DataRow(
                        cells: [
                          DataCell(Text(item.nombre)),
                          DataCell(
                            Text(item.tipo == 'INSUMO' ? 'Insumo' : 'Producto'),
                          ),
                          DataCell(Text(formatQty(item.stock))),
                          DataCell(Text(formatQty(item.stockMinimo))),
                          DataCell(Text(formatMoney(item.costoUnitario))),
                          DataCell(Text(formatMoney(item.valor))),
                          DataCell(
                            item.alerta
                                ? Chip(
                                    label: const Text('Bajo'),
                                    side: BorderSide.none,
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .errorContainer,
                                  )
                                : const Text('OK'),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _faltantesTab(BuildContext context, _ReportData data) {
    if (data.faltantes.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Sin faltantes en el período',
        message: 'Ninguna venta consumió más insumos de los disponibles.',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final total = data.faltantes.fold<double>(
      0,
      (sum, item) => sum + item.costoFaltante,
    );
    return ListView(
      padding: EdgeInsets.all(
        esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
      ),
      children: [
        StatGrid(
          children: [
            StatCard(
              label: 'Eventos registrados',
              value: '${data.faltantes.length}',
              icon: Icons.warning_amber_rounded,
              color: scheme.error,
            ),
            StatCard(
              label: 'Costo del faltante',
              value: formatMoney(total),
              icon: Icons.price_check,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Fecha')),
                DataColumn(label: Text('Pedido')),
                DataColumn(label: Text('Producto')),
                DataColumn(label: Text('Insumo')),
                DataColumn(label: Text('Requerido'), numeric: true),
                DataColumn(label: Text('Disponible'), numeric: true),
                DataColumn(label: Text('Faltante'), numeric: true),
                DataColumn(label: Text('Costo'), numeric: true),
              ],
              rows: data.faltantes
                  .map(
                    (item) => DataRow(
                      cells: [
                        DataCell(Text(formatDateTimeShort(item.fecha))),
                        DataCell(Text(item.referencia ?? '—')),
                        DataCell(Text(item.producto)),
                        DataCell(Text(item.insumo)),
                        DataCell(
                          Text(
                            '${formatQty(item.requerido)} ${item.unidad}',
                          ),
                        ),
                        DataCell(
                          Text(
                            '${formatQty(item.disponible)} ${item.unidad}',
                          ),
                        ),
                        DataCell(
                          Text(
                            '${formatQty(item.faltante)} ${item.unidad}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: scheme.error,
                            ),
                          ),
                        ),
                        DataCell(Text(formatMoney(item.costoFaltante))),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _imprimirPedido(PedidoReporte pedido) async {
    try {
      final detalle = await SalesRepository().getPedido(pedido.id);
      await ReceiptService().imprimirNotaVenta(
        detalle: detalle,
        turno: pedido.turnoLabel,
        cajero: pedido.usuario,
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No se pudo generar la nota de venta: $error',
        error: true,
      );
    }
  }

  Widget _pedidosTab(BuildContext context, _ReportData data) {
    if (data.pedidos.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Sin pedidos en el período',
        message: 'No hay pedidos registrados para mostrar.',
      );
    }
    return ListView(
      padding: EdgeInsets.all(
        esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
      ),
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Pedido')),
                DataColumn(label: Text('Fecha')),
                DataColumn(label: Text('Cajero')),
                DataColumn(label: Text('Turno')),
                DataColumn(label: Text('Total'), numeric: true),
                DataColumn(label: Text('Efectivo'), numeric: true),
                DataColumn(label: Text('QR'), numeric: true),
                DataColumn(label: Text('Estado')),
                DataColumn(label: Text('Nota')),
              ],
              rows: data.pedidos
                  .map(
                    (pedido) => DataRow(
                      cells: [
                        DataCell(
                          Text(
                            pedido.referencia == null
                                ? '#${pedido.id}'
                                : '${pedido.referencia} · #${pedido.id}',
                          ),
                        ),
                        DataCell(Text(formatDateTimeText(pedido.fecha))),
                        DataCell(Text(pedido.usuario)),
                        DataCell(Text(pedido.turnoLabel)),
                        DataCell(Text(formatMoney(pedido.total))),
                        DataCell(Text(formatMoney(pedido.efectivo))),
                        DataCell(Text(formatMoney(pedido.qr))),
                        DataCell(Text(pedido.estadoPago)),
                        DataCell(
                          IconButton(
                            tooltip: 'Imprimir nota de venta',
                            onPressed: () => _imprimirPedido(pedido),
                            icon: const Icon(Icons.print_outlined),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _TabBarHeader extends SliverPersistentHeaderDelegate {
  const _TabBarHeader({required this.tabBar, required this.color});

  final TabBar tabBar;
  final Color color;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(color: color, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarHeader oldDelegate) =>
      oldDelegate.tabBar != tabBar || oldDelegate.color != color;
}
