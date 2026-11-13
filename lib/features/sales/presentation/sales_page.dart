import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/cash_repository.dart';
import '../../../core/catalog_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/menu_repository.dart';
import '../../../core/receipt_service.dart';
import '../../../core/sales_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';
import '../../../ui/producto_catalogo_card.dart';

class _SaleProduct {
  const _SaleProduct({
    required this.productoId,
    this.menuDiaItemId,
    this.menuDiaComboId,
    required this.nombre,
    required this.precio,
    required this.categoriaNombre,
    this.categoriaPadreNombre,
    required this.categoriaColor,
    required this.tipo,
    required this.disponible,
    this.motivo,
    this.advertencia,
    required this.stock,
    required this.enMenu,
    this.imagen,
  });

  final int productoId;
  final int? menuDiaItemId;
  final int? menuDiaComboId;
  final String nombre;
  final double precio;
  final String categoriaNombre;
  final String? categoriaPadreNombre;
  final int categoriaColor;
  final String tipo;
  final bool disponible;
  final String? motivo;
  final String? advertencia;
  final double stock;
  final bool enMenu;
  final Uint8List? imagen;

  bool get esDirecto => tipo == 'DIRECTO';

  String get categoriaEtiqueta => categoriaPadreNombre == null
      ? categoriaNombre
      : '$categoriaPadreNombre · $categoriaNombre';

  /// Solo lo que está en el menú habilitado se puede vender.
  bool get vendible => enMenu && disponible && (!esDirecto || stock > 0);

  String get razon {
    if (!enMenu) return 'Fuera del menú de hoy';
    if (!disponible) return motivo ?? 'Agotado';
    if (esDirecto && stock <= 0) return 'Sin stock';
    return '';
  }
}

class _SalesData {
  const _SalesData({
    required this.caja,
    required this.menu,
    required this.productos,
    required this.pedidosAbiertos,
  });

  final Caja? caja;
  final MenuDia? menu;
  final List<_SaleProduct> productos;
  final List<Pedido> pedidosAbiertos;
}

class SalesPage extends StatefulWidget {
  const SalesPage({
    super.key,
    required this.usuario,
    required this.refreshToken,
    this.onAbrirCaja,
  });

  final Usuario usuario;
  final int refreshToken;
  final VoidCallback? onAbrirCaja;

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _cashRepository = CashRepository();
  final _catalogRepository = CatalogRepository();
  final _menuRepository = MenuRepository();
  final _salesRepository = SalesRepository();
  late Future<_SalesData> _future;
  final _cart = <int, CartLine>{};
  final _referencia = TextEditingController();
  final _observacion = TextEditingController();
  String _search = '';
  String? _categoria;
  int? _pedidoEditandoId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(SalesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reload();
  }

  @override
  void dispose() {
    _referencia.dispose();
    _observacion.dispose();
    super.dispose();
  }

  // Debe devolver void: si devolviera el Future, setState lanzaría error y la
  // pantalla no se refrescaría.
  void _reload() {
    _future = _load();
  }

  Future<_SalesData> _load() async {
    final caja = await _cashRepository.getCajaAbierta();
    final now = DateTime.now();
    final menu = await _menuRepository.getMenu(now, MenuRepository.tipoMenu);
    final menuItems = menu != null && menu.habilitado
        ? await _menuRepository.getItems(menu.id)
        : <MenuItem>[];
    final combos = menu != null && menu.habilitado
        ? await _menuRepository.getCombos(menu.id)
        : <MenuCombo>[];

    final productos = <int, _SaleProduct>{};
    for (final combo in combos) {
      final producto = await _catalogRepository.getProducto(combo.productoId);
      productos[combo.productoId] = _SaleProduct(
        productoId: combo.productoId,
        menuDiaComboId: combo.id,
        nombre: combo.nombre,
        precio: combo.precio,
        categoriaNombre: 'ALMUERZOS Y COMBOS',
        categoriaColor: combo.categoriaColor,
        tipo: 'PREPARADO',
        disponible: combo.disponible,
        motivo: combo.disponible ? null : 'Combo agotado',
        stock: producto?.stock ?? 0,
        enMenu: true,
        imagen: combo.imagen,
      );
    }
    for (final item in menuItems) {
      final producto = await _catalogRepository.getProducto(item.productoId);
      final advertencia = await _catalogRepository.advertenciaInsumos(
        item.productoId,
        1,
      );
      productos[item.productoId] = _SaleProduct(
        productoId: item.productoId,
        menuDiaItemId: item.id,
        nombre: item.nombre,
        precio: item.precio,
        categoriaNombre: item.categoriaNombre,
        categoriaPadreNombre: producto?.categoriaParentNombre,
        categoriaColor: item.categoriaColor,
        tipo: item.tipoProducto,
        disponible: item.disponible,
        motivo: item.motivoAgotado,
        advertencia: advertencia,
        stock: producto?.stock ?? 0,
        enMenu: true,
        imagen: producto?.imagen,
      );
    }
    // Productos activos que no están en el menú: se muestran al final, en gris.
    // Los de categorías "siempre disponibles" (venta directa) se pueden vender
    // aunque no estén en el menú del día.
    final activos = await _catalogRepository.getProductos(soloActivos: true);
    for (final producto in activos) {
      if (productos.containsKey(producto.id)) continue;
      final siempre =
          producto.categoriaSiempreDisponible || producto.esVentaDirecta;
      String? motivo;
      String? advertencia;
      var disponible = false;
      if (siempre) {
        motivo = await _catalogRepository.motivoNoDisponible(producto.id!, 1);
        disponible = motivo == null;
        if (disponible) {
          advertencia = await _catalogRepository.advertenciaInsumos(
            producto.id!,
            1,
          );
        }
      }
      productos[producto.id!] = _SaleProduct(
        productoId: producto.id!,
        nombre: producto.nombre,
        precio: producto.precio,
        categoriaNombre: producto.categoriaNombre,
        categoriaPadreNombre: producto.categoriaParentNombre,
        categoriaColor: producto.categoriaColor,
        tipo: producto.tipo,
        disponible: disponible,
        motivo: motivo,
        advertencia: advertencia,
        stock: producto.stock,
        enMenu: siempre,
        imagen: producto.imagen,
      );
    }
    final abiertos = await _salesRepository.getPedidosAbiertos();
    return _SalesData(
      caja: caja,
      menu: menu,
      productos: productos.values.toList(),
      pedidosAbiertos: abiertos,
    );
  }

  double get _total =>
      _cart.values.fold<double>(0, (sum, line) => sum + line.subtotal);

  int get _unidades =>
      _cart.values.fold<int>(0, (sum, line) => sum + line.cantidad.round());

  void _add(_SaleProduct producto) {
    if (!producto.vendible) {
      showAppMessage(
        context,
        producto.motivo ?? 'El producto no está disponible.',
        error: true,
      );
      return;
    }
    setState(() {
      final line = _cart[producto.productoId];
      if (line == null) {
        _cart[producto.productoId] = CartLine(
          productoId: producto.productoId,
          menuDiaItemId: producto.menuDiaItemId,
          menuDiaComboId: producto.menuDiaComboId,
          nombre: producto.nombre,
          precio: producto.precio,
          cantidad: 1,
          tipo: producto.tipo,
        );
      } else {
        _cart[producto.productoId] = line.copyWith(cantidad: line.cantidad + 1);
      }
    });
  }

  void _changeQty(int productoId, double delta) {
    setState(() {
      final line = _cart[productoId];
      if (line == null) return;
      final nueva = line.cantidad + delta;
      if (nueva <= 0) {
        _cart.remove(productoId);
      } else {
        _cart[productoId] = line.copyWith(cantidad: nueva);
      }
    });
  }

  void _remove(int productoId) {
    setState(() => _cart.remove(productoId));
  }

  void _limpiarCarrito() {
    setState(() {
      _cart.clear();
      _referencia.clear();
      _observacion.clear();
      _pedidoEditandoId = null;
    });
  }

  Future<void> _guardarPendiente(_SalesData data) async {
    final caja = data.caja;
    if (caja == null) return;
    if (_cart.isEmpty) {
      showAppMessage(context, 'Agrega productos al pedido.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      if (_pedidoEditandoId != null) {
        await _salesRepository.agregarLineas(
          _pedidoEditandoId!,
          _cart.values.toList(),
          cajaId: caja.id,
        );
      } else {
        await _salesRepository.crearPedido(
          usuarioId: widget.usuario.id,
          cajaId: caja.id,
          menuDiaId: data.menu?.habilitado == true ? data.menu!.id : null,
          referencia: _referencia.text,
          observacion: _observacion.text,
          lineas: _cart.values.toList(),
          pagos: const [],
        );
      }
      if (!mounted) return;
      final editando = _pedidoEditandoId;
      _limpiarCarrito();
      setState(() {
        _saving = false;
        _reload();
      });
      showAppMessage(
        context,
        editando == null
            ? 'Pedido guardado como pendiente de pago.'
            : 'Líneas agregadas al pedido.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, '$error', error: true);
    }
  }

  Future<void> _cobrar(_SalesData data) async {
    final caja = data.caja;
    if (caja == null) return;
    if (_cart.isEmpty) {
      showAppMessage(context, 'Agrega productos al pedido.', error: true);
      return;
    }
    final pagos = await showDialog<List<PagoInput>>(
      context: context,
      builder: (_) => _PaymentDialog(total: _total),
    );
    if (pagos == null) return;
    setState(() => _saving = true);
    try {
      final int pedidoId;
      final editando = _pedidoEditandoId;
      if (editando != null) {
        pedidoId = editando;
        await _salesRepository.agregarLineas(
          pedidoId,
          _cart.values.toList(),
          cajaId: caja.id,
        );
        await _salesRepository.agregarPagos(
          pedidoId: pedidoId,
          usuarioId: widget.usuario.id,
          cajaId: caja.id,
          pagos: pagos,
        );
      } else {
        pedidoId = await _salesRepository.crearPedido(
          usuarioId: widget.usuario.id,
          cajaId: caja.id,
          menuDiaId: data.menu?.habilitado == true ? data.menu!.id : null,
          referencia: _referencia.text,
          observacion: _observacion.text,
          lineas: _cart.values.toList(),
          pagos: pagos,
        );
      }
      final detalle = await _salesRepository.getPedido(pedidoId);
      if (!mounted) return;
      _limpiarCarrito();
      setState(() {
        _saving = false;
        _reload();
      });
      showAppMessage(
        context,
        editando == null
            ? 'Venta registrada por ${formatMoney(_totalAnterior(pagos))}.'
            : 'Pago agregado al pedido.',
      );
      if (detalle.pedido.pagadoCompleto) {
        await _ofrecerImprimir(detalle, caja);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, '$error', error: true);
    }
  }

  double _totalAnterior(List<PagoInput> pagos) =>
      pagos.fold<double>(0, (sum, pago) => sum + pago.monto);

  Future<void> _cobrarPedido(Pedido pedido, _SalesData data) async {
    final caja = data.caja;
    if (caja == null) {
      showAppMessage(
        context,
        'Abre una caja para cobrar pedidos pendientes.',
        error: true,
      );
      return;
    }
    final pagos = await showDialog<List<PagoInput>>(
      context: context,
      builder: (_) => _PaymentDialog(total: pedido.saldo),
    );
    if (pagos == null) return;
    try {
      await _salesRepository.agregarPagos(
        pedidoId: pedido.id,
        usuarioId: widget.usuario.id,
        cajaId: caja.id,
        pagos: pagos,
      );
      final detalle = await _salesRepository.getPedido(pedido.id);
      if (!mounted) return;
      setState(_reload);
      showAppMessage(context, 'Pago registrado para el pedido #${pedido.id}.');
      if (detalle.pedido.pagadoCompleto) {
        await _ofrecerImprimir(detalle, caja);
      }
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, '$error', error: true);
    }
  }

  Future<void> _ofrecerImprimir(PedidoDetalle detalle, Caja caja) async {
    final imprimir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nota de venta'),
        content: Text(
          '¿Deseas imprimir la nota de venta del pedido #${detalle.pedido.id}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Sí, imprimir'),
          ),
        ],
      ),
    );
    if (imprimir != true) return;
    try {
      await ReceiptService().imprimirNotaVenta(
        detalle: detalle,
        turno: caja.turnoLabel,
        cajero: widget.usuario.nombre,
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

  Future<void> _anular(Pedido pedido) async {
    final confirmado = await confirmAction(
      context,
      title: 'Anular pedido',
      message:
          'Se anularán el pedido #${pedido.id}, sus pagos y los consumos de insumos asociados.',
      confirmLabel: 'Anular',
      destructive: true,
    );
    if (!confirmado) return;
    try {
      await _salesRepository.anularPedido(pedido.id);
      if (!mounted) return;
      setState(_reload);
      showAppMessage(context, 'Pedido anulado.');
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, 'No se pudo anular: $error', error: true);
    }
  }

  Future<void> _verPedido(Pedido pedido) async {
    try {
      final detalle = await _salesRepository.getPedido(pedido.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _PedidoDetalleDialog(detalle: detalle),
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No se pudo cargar el pedido: $error',
        error: true,
      );
    }
  }

  Future<void> _agotar(_SaleProduct producto) async {
    final menuItemId = producto.menuDiaItemId;
    final comboId = producto.menuDiaComboId;
    if (menuItemId == null && comboId == null) return;
    final confirmado = await confirmAction(
      context,
      title: 'Reportar agotamiento',
      message:
          '${producto.nombre} dejará de estar disponible para la venta de hoy.',
      confirmLabel: 'Marcar agotado',
      destructive: true,
    );
    if (!confirmado) return;
    if (comboId != null) {
      await _menuRepository.setComboDisponible(comboId, false);
    } else {
      await _menuRepository.setDisponible(menuItemId!, false, motivo: 'Agotado');
    }
    if (!mounted) return;
    setState(_reload);
    showAppMessage(context, '${producto.nombre} marcado como agotado.');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SalesData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return SingleChildScrollView(
          padding: EdgeInsets.all(
            esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Ventas',
                subtitle: 'Toca el producto para agregarlo al pedido. Solo se venden los del menú habilitado.',
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
              else if (data == null)
                const SizedBox.shrink()
              else if (data.caja == null)
                Column(
                  children: [
                    EmptyState(
                      icon: Icons.lock_outline,
                      title: 'No hay caja abierta',
                      message: 'Abre una caja en la sección Caja para registrar ventas.',
                      action: widget.onAbrirCaja == null
                          ? null
                          : FilledButton.icon(
                              onPressed: widget.onAbrirCaja,
                              icon: const Icon(
                                Icons.account_balance_wallet_outlined,
                              ),
                              label: const Text('Ir a Caja'),
                            ),
                    ),
                    if (data.pedidosAbiertos.isNotEmpty)
                      _pedidosAbiertos(context, data),
                  ],
                )
              else ...[
                _estadoMenu(context, data),
                const SizedBox(height: 14),
                _filtros(context, data),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontal = constraints.maxWidth >= 1000;
                    final catalogo = _catalogo(context, data);
                    final carrito = _carrito(context, data);
                    if (horizontal) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: catalogo),
                          const SizedBox(width: 16),
                          SizedBox(width: 390, child: carrito),
                        ],
                      );
                    }
                    return Column(
                      children: [catalogo, const SizedBox(height: 16), carrito],
                    );
                  },
                ),
                const SizedBox(height: 22),
                _pedidosAbiertos(context, data),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _estadoMenu(BuildContext context, _SalesData data) {
    final scheme = Theme.of(context).colorScheme;
    final menu = data.menu;
    final habilitado = menu?.habilitado == true;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            habilitado ? Icons.check_circle_outline : Icons.info_outline,
            color: habilitado ? scheme.primary : scheme.tertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              habilitado
                  ? 'Menú de ${menu!.tipo.toLowerCase()} habilitado. ${data.caja!.turnoLabel}.'
                  : 'No hay menú habilitado para hoy. El administrador debe habilitarlo para poder vender.',
            ),
          ),
          Chip(
            label: Text(data.caja!.turnoLabel),
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _filtros(BuildContext context, _SalesData data) {
    final categorias = data.productos
        .map((producto) => producto.categoriaNombre)
        .toSet()
        .toList()
      ..sort();
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              decoration: appInput(
                label: 'Buscar producto',
                icon: Icons.search,
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          ChoiceChip(
            label: const Text('Todas'),
            selected: _categoria == null,
            onSelected: (_) => setState(() => _categoria = null),
          ),
          ...categorias.map(
            (categoria) => ChoiceChip(
              label: Text(categoria),
              selected: _categoria == categoria,
              onSelected: (_) => setState(() => _categoria = categoria),
            ),
          ),
        ],
      ),
    );
  }

  Widget _catalogo(BuildContext context, _SalesData data) {
    final filtrados = data.productos.where((producto) {
      if (_categoria != null && producto.categoriaNombre != _categoria) {
        return false;
      }
      final term = _search.trim().toLowerCase();
      return term.isEmpty || producto.nombre.toLowerCase().contains(term);
    }).toList();
    if (filtrados.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'No hay productos disponibles',
        message: 'Crea productos activos en Productos y publícalos en el Menú del día.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: filtrados.map((producto) {
            final cantidad = _cart[producto.productoId]?.cantidad.round() ?? 0;
            return SizedBox(
              width: width,
              child: ProductoCatalogoCard(
                nombre: producto.nombre,
                categoria: producto.categoriaEtiqueta,
                precio: producto.precio,
                color: producto.categoriaColor,
                imagen: producto.imagen,
                esDirecto: producto.esDirecto,
                stock: producto.stock,
                habilitado: producto.vendible,
                mensaje: producto.vendible
                    ? (cantidad > 0
                          ? 'Toca para agregar · $cantidad en el pedido'
                          : 'Toca para agregar')
                    : producto.razon,
                onTap: producto.vendible ? () => _add(producto) : null,
                advertencia: producto.vendible ? producto.advertencia : null,
                accion:
                    (producto.menuDiaItemId != null ||
                            producto.menuDiaComboId != null) &&
                        widget.usuario.puede(Permiso.agotamiento)
                    ? IconButton(
                        tooltip: 'Reportar agotado',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _agotar(producto),
                        icon: const Icon(Icons.block, size: 18),
                      )
                    : null,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _carrito(BuildContext context, _SalesData data) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_cart_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Pedido',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '$_unidades ítem(s)',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          if (_pedidoEditandoId != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Agregando líneas al pedido #$_pedidoEditandoId',
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _pedidoEditandoId = null),
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (_cart.isEmpty)
            const EmptyState(
              icon: Icons.add_shopping_cart,
              title: 'Carrito vacío',
              message: 'Toca un producto para agregarlo al pedido.',
            )
          else ...[
            ..._cart.values.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final angosto = esAngosto(
                      constraints.maxWidth,
                      limite: 460,
                    );
                    final info = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.nombre,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${formatMoney(line.precio)} c/u',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    );
                    final controles = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _changeQty(line.productoId, -1),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          formatQty(line.cantidad),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _changeQty(line.productoId, 1),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    );
                    final subtotal = Text(
                      formatMoney(line.subtotal),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    );
                    final quitar = IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Quitar',
                      onPressed: () => _remove(line.productoId),
                      icon: const Icon(Icons.close, size: 18),
                    );
                    if (angosto) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: info),
                              quitar,
                            ],
                          ),
                          Row(children: [controles, const Spacer(), subtotal]),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: info),
                        controles,
                        SizedBox(width: 70, child: subtotal),
                        quitar,
                      ],
                    );
                  },
                ),
              ),
            ),
            const Divider(height: 20),
            Row(
              children: [
                Text('Total', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  formatMoney(_total),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _referencia,
              decoration: appInput(
                label: 'Referencia (opcional)',
                hint: 'Ej. mesa 3, nombre o nota',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _observacion,
              maxLines: 2,
              decoration: appInput(label: 'Observación (opcional)'),
            ),
            const SizedBox(height: 14),
            if (_pedidoEditandoId != null)
              FilledButton.icon(
                onPressed: _saving ? null : () => _guardarPendiente(data),
                icon: const Icon(Icons.playlist_add),
                label: Text(_saving ? 'Guardando…' : 'Agregar al pedido'),
              )
            else ...[
              FilledButton.icon(
                onPressed: _saving ? null : () => _cobrar(data),
                icon: const Icon(Icons.point_of_sale),
                label: const Text('Pagado'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _guardarPendiente(data),
                icon: const Icon(Icons.pending_actions_outlined),
                label: const Text('Guardar pendiente de pago'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _pedidosAbiertos(BuildContext context, _SalesData data) {
    if (data.pedidosAbiertos.isEmpty) {
      return const SizedBox.shrink();
    }
    final hayCaja = data.caja != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pedidos pendientes de pago',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (!hayCaja) ...[
          const SizedBox(height: 4),
          Text(
            'Abre una caja para cobrar o modificar pedidos pendientes.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 10),
        ...data.pedidosAbiertos.map(
          (pedido) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final angosto = esAngosto(constraints.maxWidth, limite: 820);
                  final cabecera = Row(
                    children: [
                      CircleAvatar(radius: 18, child: Text('${pedido.id}')),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pedido.referencia == null
                                  ? 'Pedido #${pedido.id}'
                                  : '${pedido.referencia} · #${pedido.id}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${formatDateTimeText(pedido.fecha)} · ${pedido.usuarioNombre}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                  final montos = Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total ${formatMoney(pedido.total)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Saldo ${formatMoney(pedido.saldo)}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  );
                  final acciones = Wrap(
                    spacing: 2,
                    runSpacing: 0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Ver detalle',
                        onPressed: () => _verPedido(pedido),
                        icon: const Icon(Icons.visibility_outlined),
                      ),
                      TextButton(
                        onPressed: hayCaja
                            ? () => _cobrarPedido(pedido, data)
                            : null,
                        child: const Text('Cobrar'),
                      ),
                      TextButton(
                        onPressed: hayCaja
                            ? () {
                                setState(() => _pedidoEditandoId = pedido.id);
                                showAppMessage(
                                  context,
                                  'Agrega productos y usa “Agregar al pedido”.',
                                );
                              }
                            : null,
                        child: const Text('Agregar'),
                      ),
                      TextButton(
                        onPressed: () => _anular(pedido),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        child: const Text('Anular'),
                      ),
                    ],
                  );
                  if (angosto) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        cabecera,
                        const SizedBox(height: 8),
                        montos,
                        acciones,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(flex: 2, child: cabecera),
                      Expanded(child: montos),
                      acciones,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.total});

  final double total;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final TextEditingController _efectivo;
  late final TextEditingController _qr;

  @override
  void initState() {
    super.initState();
    _efectivo = TextEditingController(text: widget.total.toStringAsFixed(2));
    _qr = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _efectivo.dispose();
    _qr.dispose();
    super.dispose();
  }

  double get _suma => parseAmount(_efectivo.text) + parseAmount(_qr.text);

  double get _restante => widget.total - _suma;

  bool get _completo => _suma > 0 && _restante.abs() <= 0.05;

  bool get _excede => _restante < -0.05;

  void _actualizar(String metodo, String value) {
    final monto = parseAmount(value);
    final complemento = (widget.total - monto).clamp(0.0, widget.total);
    setState(() {
      if (metodo == 'EFECTIVO') {
        _qr.text = complemento.toStringAsFixed(2);
      } else {
        _efectivo.text = complemento.toStringAsFixed(2);
      }
    });
  }

  void _todo(String metodo) {
    setState(() {
      _efectivo.text = metodo == 'EFECTIVO'
          ? widget.total.toStringAsFixed(2)
          : '0';
      _qr.text = metodo == 'QR' ? widget.total.toStringAsFixed(2) : '0';
    });
  }

  void _confirmar() {
    final pagos = <PagoInput>[];
    final efectivo = parseAmount(_efectivo.text);
    final qr = parseAmount(_qr.text);
    if (efectivo > 0) {
      pagos.add(PagoInput(metodo: 'EFECTIVO', monto: efectivo));
    }
    if (qr > 0) {
      pagos.add(PagoInput(metodo: 'QR', monto: qr));
    }
    Navigator.pop(context, pagos);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: const Text('Cobrar pedido'),
      content: DialogSurface(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Total a cobrar'),
                const Spacer(),
                Text(
                  formatMoney(widget.total),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'El otro método se completa automáticamente.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _efectivo,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: appInput(
                label: 'Efectivo (Bs)',
                icon: Icons.payments_outlined,
              ),
              onChanged: (value) => _actualizar('EFECTIVO', value),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _qr,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: appInput(label: 'QR (Bs)', icon: Icons.qr_code_2),
              onChanged: (value) => _actualizar('QR', value),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    label: const Text('Todo efectivo'),
                    onPressed: () => _todo('EFECTIVO'),
                  ),
                  ActionChip(
                    label: const Text('Todo QR'),
                    onPressed: () => _todo('QR'),
                  ),
                ],
              ),
            ),
            const Divider(),
            Row(
              children: [
                Text(
                  _restante > 0.004
                      ? 'Restante'
                      : _restante < -0.004
                      ? 'Excede el total'
                      : 'Completo',
                  style: TextStyle(
                    color: _restante.abs() <= 0.004
                        ? scheme.primary
                        : scheme.error,
                  ),
                ),
                const Spacer(),
                Text(
                  formatMoney(_restante.abs()),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _restante.abs() <= 0.004
                        ? scheme.primary
                        : scheme.error,
                  ),
                ),
              ],
            ),
            if (_excede)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Los pagos no pueden superar el total.',
                  style: TextStyle(color: scheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _completo ? _confirmar : null,
          child: const Text('Confirmar pago'),
        ),
      ],
    );
  }
}

class _PedidoDetalleDialog extends StatelessWidget {
  const _PedidoDetalleDialog({required this.detalle});

  final PedidoDetalle detalle;

  @override
  Widget build(BuildContext context) {
    final pedido = detalle.pedido;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text('Pedido #${pedido.id}'),
      content: DialogSurface(
        maxWidth: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabelValue(label: 'Estado de pago', value: pedido.estadoPago),
              LabelValue(
                label: 'Estado de entrega',
                value: pedido.estadoEntrega,
              ),
              if (pedido.referencia != null)
                LabelValue(label: 'Referencia', value: pedido.referencia!),
              LabelValue(
                label: 'Fecha',
                value: formatDateTimeText(pedido.fecha),
              ),
              LabelValue(label: 'Total', value: formatMoney(pedido.total)),
              LabelValue(label: 'Pagado', value: formatMoney(pedido.pagado)),
              LabelValue(label: 'Saldo', value: formatMoney(pedido.saldo)),
              const Divider(height: 22),
              Text(
                'Productos',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ...detalle.lineas.where((linea) => !linea.esComponente).map(
                (linea) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${formatQty(linea.cantidad)} × ${linea.nombre}',
                        ),
                      ),
                      Text(formatMoney(linea.subtotal)),
                    ],
                  ),
                ),
              ),
              const Divider(height: 22),
              Text(
                'Pagos',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (detalle.pagos.isEmpty)
                const Text('Sin pagos registrados.')
              else
                ...detalle.pagos.map(
                  (pago) => Row(
                    children: [
                      Expanded(child: Text('${pago.metodo} · ${pago.estado}')),
                      Text(formatMoney(pago.monto)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
