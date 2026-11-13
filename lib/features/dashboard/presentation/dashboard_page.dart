import 'package:flutter/material.dart';

import '../../../core/cash_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/menu_repository.dart';
import '../../../core/report_repository.dart';
import '../../../core/sales_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.usuario,
    required this.refreshToken,
    this.onEmpezarDia,
  });

  final Usuario usuario;
  final int refreshToken;

  /// Flujo de inicio del día: lleva a la pantalla de Menú.
  final VoidCallback? onEmpezarDia;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardData {
  const _DashboardData({
    required this.resumen,
    required this.caja,
    required this.pedidosAbiertos,
    required this.alertas,
    required this.menu,
    required this.itemsMenu,
  });

  final ResumenFinanciero resumen;
  final Caja? caja;
  final int pedidosAbiertos;
  final List<InventarioReporte> alertas;
  final MenuDia? menu;
  final int itemsMenu;
}

class _DashboardPageState extends State<DashboardPage> {
  final _reportRepository = ReportRepository();
  final _cashRepository = CashRepository();
  final _salesRepository = SalesRepository();
  final _menuRepository = MenuRepository();
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reload();
  }

  // Debe devolver void: si devolviera el Future, setState lanzaría error y la
  // pantalla no se refrescaría.
  void _reload() {
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final resumen = await _reportRepository.getResumen(
      today,
      today.add(const Duration(days: 1)),
    );
    final caja = await _cashRepository.getCajaAbierta();
    final abiertos = await _salesRepository.getPedidosAbiertos();
    final alertas = await _reportRepository.getAlertasStock();
    final menu = await _menuRepository.getMenu(today, MenuRepository.tipoMenu);
    final items = menu == null
        ? 0
        : (await _menuRepository.getItems(menu.id)).length;
    return _DashboardData(
      resumen: resumen,
      caja: caja,
      pedidosAbiertos: abiertos.length,
      alertas: alertas,
      menu: menu,
      itemsMenu: items,
    );
  }

  String get _saludo {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días';
    if (hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final puedeReportes = widget.usuario.puede(Permiso.reportes);
    return FutureBuilder<_DashboardData>(
      future: _future,
      builder: (context, snapshot) {
        return SingleChildScrollView(
          padding: EdgeInsets.all(
            esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: '$_saludo, ${widget.usuario.nombre}',
                subtitle: formatDateShort(DateTime.now()),
                actions: [
                  OutlinedButton.icon(
                    onPressed: () => setState(_reload),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                  ),
                ],
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LoadingView()
              else if (snapshot.hasError)
                ErrorView(
                  message: '${snapshot.error}',
                  onRetry: () => setState(_reload),
                )
              else ...[
                _buildBody(context, snapshot.data!, puedeReportes),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Primer paso del día: elegir el menú y luego abrir la caja.
  Widget _empezarDiaCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final boton = FilledButton.icon(
      onPressed: widget.onEmpezarDia,
      icon: const Icon(Icons.play_arrow_rounded),
      label: const Text('Empezar el día'),
    );
    return AppCard(
      color: scheme.primaryContainer.withValues(alpha: 0.45),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final icono = Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.wb_sunny_outlined,
              color: scheme.onPrimary, // Blanco cálido
              size: 28,
            ),
          );
          final texto = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Empezar el día',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                'Elige el menú de hoy y después abre la caja para iniciar.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          );
          if (esAngosto(constraints.maxWidth, limite: 560)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    icono,
                    const SizedBox(width: 14),
                    Expanded(child: texto),
                  ],
                ),
                const SizedBox(height: 12),
                boton,
              ],
            );
          }
          return Row(
            children: [
              icono,
              const SizedBox(width: 16),
              Expanded(child: texto),
              const SizedBox(width: 12),
              boton,
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    _DashboardData data,
    bool puedeReportes,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final puedeMenu = widget.usuario.puede(Permiso.menu);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.caja == null && puedeMenu) ...[
          _empezarDiaCard(context),
          const SizedBox(height: 16),
        ],
        if (data.caja == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AppCard(
              color: scheme.errorContainer.withValues(alpha: 0.35),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: scheme.error),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'No hay una caja abierta. Abre la caja para poder registrar ventas.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (puedeReportes)
          StatGrid(
            children: [
              StatCard(
                label: 'Ventas del día',
                value: formatMoney(data.resumen.ventas),
                caption:
                    'Efectivo ${formatMoney(data.resumen.cobrosEfectivo)} · QR ${formatMoney(data.resumen.cobrosQr)}',
                icon: Icons.trending_up,
              ),
              StatCard(
                label: 'Gasto en insumos',
                value: formatMoney(data.resumen.gastoInsumos),
                caption: 'Lo que entró de insumos al stock',
                icon: Icons.shopping_basket_outlined,
                color: scheme.secondary,
              ),
              StatCard(
                label: 'Salidas de emergencia',
                value: formatMoney(data.resumen.salidas),
                caption: 'Gastos pagados del día',
                icon: Icons.outbox,
                color: scheme.tertiary,
              ),
              StatCard(
                label: 'Ganancia',
                value: formatMoney(data.resumen.ganancia),
                caption: 'Ventas − gasto en insumos − salidas',
                icon: Icons.insights,
                color: data.resumen.ganancia >= 0 ? scheme.primary : scheme.error,
              ),
            ],
          )
        else
          StatGrid(
            children: [
              StatCard(
                label: 'Pedidos abiertos',
                value: '${data.pedidosAbiertos}',
                icon: Icons.pending_actions_outlined,
              ),
              StatCard(
                label: 'Caja',
                value: data.caja == null ? 'Cerrada' : 'Abierta',
                caption: data.caja == null
                    ? 'Abre una caja para vender'
                    : data.caja!.turnoLabel,
                icon: Icons.account_balance_wallet_outlined,
                color: data.caja == null ? scheme.error : scheme.primary,
              ),
              StatCard(
                label: 'Alertas de stock',
                value: '${data.alertas.length}',
                icon: Icons.inventory_2_outlined,
                color: data.alertas.isEmpty ? scheme.primary : scheme.error,
              ),
            ],
          ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 980;
            final caja = _cajaCard(context, data.caja);
            final alertas = _alertasCard(context, data.alertas);
            final menu = _menuCard(context, data.menu, data.itemsMenu);
            if (horizontal) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: caja),
                  const SizedBox(width: 16),
                  Expanded(child: menu),
                  const SizedBox(width: 16),
                  Expanded(child: alertas),
                ],
              );
            }
            return Column(
              children: [
                caja,
                const SizedBox(height: 12),
                menu,
                const SizedBox(height: 12),
                alertas,
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        if (puedeReportes) _resumenDetallado(context, data.resumen),
      ],
    );
  }

  Widget _cajaCard(BuildContext context, Caja? caja) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Caja',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Chip(
                label: Text(caja == null ? 'Cerrada' : 'Abierta'),
                backgroundColor: caja == null
                    ? scheme.errorContainer
                    : scheme.primaryContainer,
                side: BorderSide.none,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (caja == null)
            Text(
              'Sin turno activo. Abre la caja desde la sección Caja.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else ...[
            LabelValue(label: 'Turno', value: caja.turnoLabel),
            LabelValue(
              label: 'Fondo inicial',
              value: formatMoney(caja.fondoInicial),
            ),
            LabelValue(
              label: 'Apertura',
              value: formatDateTimeText(caja.fechaApertura),
            ),
            LabelValue(label: 'Responsable', value: caja.usuarioApertura),
          ],
        ],
      ),
    );
  }

  Widget _menuCard(BuildContext context, MenuDia? menu, int items) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant_menu, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Menú de hoy',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (menu == null)
            Text(
              'Aún no se creó el menú del día.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else ...[
            LabelValue(label: 'Tipo', value: menu.tipo),
            LabelValue(
              label: 'Estado',
              value: switch (menu.estado) {
                'HABILITADO' => 'Habilitado',
                'CERRADO' => 'Cerrado',
                _ => 'Borrador',
              },
            ),
            LabelValue(label: 'Platos', value: '$items'),
            if (menu.observacion != null)
              LabelValue(label: 'Nota', value: menu.observacion!),
          ],
        ],
      ),
    );
  }

  Widget _alertasCard(BuildContext context, List<InventarioReporte> alertas) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                color: alertas.isEmpty ? scheme.primary : scheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Alertas de stock',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${alertas.length}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: alertas.isEmpty ? scheme.primary : scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (alertas.isEmpty)
            Text(
              'Todo el inventario está por encima del mínimo.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            ...alertas
                .take(6)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: scheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item.nombre)),
                        Text(
                          '${formatQty(item.stock)} / ${formatQty(item.stockMinimo)}',
                          style: TextStyle(color: scheme.error),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _resumenDetallado(BuildContext context, ResumenFinanciero resumen) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen financiero de hoy',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 3 : 1;
              final items = [
                LabelValue(
                  label: 'Ventas',
                  value: formatMoney(resumen.ventas),
                  strong: true,
                ),
                LabelValue(
                  label: 'Gasto en insumos',
                  value: formatMoney(resumen.gastoInsumos),
                ),
                LabelValue(
                  label: 'Salidas de emergencia',
                  value: formatMoney(resumen.salidas),
                ),
                LabelValue(
                  label: 'Ticket promedio',
                  value: formatMoney(resumen.ticketPromedio),
                ),
              ];
              if (columns == 1) return Column(children: items);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < columns; i++)
                    Expanded(
                      child: Column(
                        children: [
                          for (var j = i; j < items.length; j += columns)
                            items[j],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ganancia (ventas − gasto en insumos − salidas)',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              Text(
                formatMoney(resumen.ganancia),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: resumen.ganancia >= 0 ? scheme.primary : scheme.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
