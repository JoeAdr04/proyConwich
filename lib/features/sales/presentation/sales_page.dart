import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/cash_repository.dart';
import '../../../core/catalog_repository.dart';
import '../../../core/date_utils.dart';
import '../../../core/menu_repository.dart';
import '../../../core/printer/printer_service.dart';
import '../../../core/sales_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';
import '../../../ui/producto_catalogo_card.dart';

class _SaleProduct {
  const _SaleProduct({
    required this.productoId,
    this.menuDiaItemId,
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
    this.activo = true,
    this.agotado = false,
    this.costoUnitario = 0,
    this.imagen,
    this.presentaciones = const [],
  });

  final int productoId;
  final int? menuDiaItemId;
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
  final double costoUnitario;
  final bool enMenu;
  final bool activo;
  final bool agotado;
  final Uint8List? imagen;

  /// Presentaciones/variantes del producto (por ejemplo, tamaños de refresco).
  final List<ProductoPresentacion> presentaciones;

  bool get esDirecto => tipo == 'DIRECTO';
  bool get esSopa => MenuRepository.esCategoriaSopa(categoriaNombre);
  bool get esPlatoSuelto =>
      MenuRepository.esCategoriaPlatoSuelto(categoriaNombre);

  String get categoriaEtiqueta => categoriaPadreNombre == null
      ? categoriaNombre
      : '$categoriaPadreNombre · $categoriaNombre';

  /// Solo lo que está en el menú habilitado se puede vender.
  bool get vendible =>
      activo && enMenu && disponible && !agotado && (!esDirecto || stock > 0);

  String get razon {
    if (!activo) return 'Producto inactivo';
    if (!enMenu) return 'Fuera del menú de hoy';
    if (agotado) return 'Agotado';
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
    required this.categorias,
    required this.pedidos,
    required this.sopaDelDia,
    required this.precioAlmuerzo,
  });

  final Caja? caja;
  final MenuDia? menu;
  final List<_SaleProduct> productos;

  /// Categorías del catálogo, en el orden canónico de la base (para los chips).
  final List<CategoriaProducto> categorias;
  final List<Pedido> pedidos;
  final _SaleProduct? sopaDelDia;

  /// Precio fijo del almuerzo completo del día, si se definió en el menú.
  final double? precioAlmuerzo;
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
  static const _categoriasParaLlevar = {
    'CAFE Y MAS',
    'MATES',
    'JUGOS',
    'FRAPEES',
  };
  final _cashRepository = CashRepository();
  final _catalogRepository = CatalogRepository();
  final _menuRepository = MenuRepository();
  final _salesRepository = SalesRepository();
  late Future<_SalesData> _future;
  final _cart = <String, CartLine>{};
  final _referencia = TextEditingController();
  final _observacion = TextEditingController();
  String _search = '';
  String? _categoria;
  bool _saving = false;
  bool _mostrarFueraMenu = false;
  bool _paraLlevar = false;
  // Llaves de los chips de categorías para desplazar la franja al elegido.
  final _chipTodasKey = GlobalKey();
  final _chipKeys = <String, GlobalKey>{};

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
    final productos = <int, _SaleProduct>{};
    // Se carga una sola vez el catálogo activo y se reutiliza para los combos,
    // los platos del menú y los productos fuera del menú. Antes se hacía una
    // consulta individual por cada producto.
    final activos = await _catalogRepository.getProductos(soloActivos: true);
    final categorias = await _catalogRepository.getCategorias();
    final productoPorId = <int, Producto>{
      for (final producto in activos)
        if (producto.id != null) producto.id!: producto,
    };
    final presentaciones = await _catalogRepository.getPresentaciones();
    for (final item in menuItems) {
      final producto = productoPorId[item.productoId];
      if (producto == null || !producto.activo) continue;
      final advertencia = await _catalogRepository.advertenciaInsumos(
        item.productoId,
        1,
        producto: producto,
      );
      productos[item.productoId] = _SaleProduct(
        productoId: item.productoId,
        menuDiaItemId: item.id,
        nombre: item.nombre,
        precio: item.precio,
        categoriaNombre: item.categoriaNombre,
        categoriaPadreNombre: producto.categoriaParentNombre,
        categoriaColor: item.categoriaColor,
        tipo: item.tipoProducto,
        disponible: item.disponible,
        motivo: item.motivoAgotado,
        advertencia: advertencia,
        stock: producto.stock,
        enMenu: true,
        activo: producto.activo,
        agotado: producto.agotado,
        costoUnitario: producto.costoUnitario,
        imagen: producto.imagen,
        presentaciones: presentaciones[item.productoId] ?? const [],
      );
    }
    // Productos activos que no están en el menú: se muestran al final, en gris.
    // Los de categorías "siempre disponibles" (venta directa) se pueden vender
    // aunque no estén en el menú del día.
    for (final producto in activos) {
      if (productos.containsKey(producto.id)) continue;
      // Los combos de días anteriores no se venden sueltos.
      if (producto.esCompuesto) continue;
      final siempre =
          producto.categoriaSiempreDisponible || producto.esVentaDirecta;
      String? motivo;
      String? advertencia;
      var disponible = false;
      if (siempre) {
        motivo = await _catalogRepository.motivoNoDisponible(
          producto.id!,
          1,
          producto: producto,
        );
        disponible = motivo == null;
        if (disponible) {
          advertencia = await _catalogRepository.advertenciaInsumos(
            producto.id!,
            1,
            producto: producto,
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
        activo: producto.activo,
        agotado: producto.agotado,
        costoUnitario: producto.costoUnitario,
        imagen: producto.imagen,
        presentaciones: presentaciones[producto.id!] ?? const [],
      );
    }
    final sopas = productos.values
        .where((producto) => producto.esSopa)
        .toList();
    final pedidos = await _salesRepository.getPedidosDelDia(now);
    return _SalesData(
      caja: caja,
      menu: menu,
      productos: productos.values.toList(),
      categorias: categorias,
      pedidos: pedidos,
      sopaDelDia: sopas.isEmpty ? null : sopas.first,
      precioAlmuerzo: menu?.precioAlmuerzo,
    );
  }

  double get _total =>
      calcularTotalPedido(_cart.values, paraLlevar: _paraLlevar);

  bool _aplicaRecargoParaLlevar(String categoria) =>
      _categoriasParaLlevar.contains(categoria.trim().toUpperCase());

  int get _unidades =>
      _cart.values.fold<int>(0, (sum, line) => sum + line.cantidad.round());

  void _add(
    _SaleProduct producto, {
    bool completo = false,
    _SaleProduct? sopa,
    double? precioAlmuerzo,
  }) {
    if (!producto.vendible) {
      showAppMessage(
        context,
        producto.motivo ?? 'El producto no está disponible.',
        error: true,
      );
      return;
    }
    if (completo &&
        (sopa == null || !sopa.vendible || !producto.esPlatoSuelto)) {
      showAppMessage(
        context,
        'La sopa del día no está disponible.',
        error: true,
      );
      return;
    }
    final modalidad = completo
        ? 'COMPLETO'
        : producto.esSopa
        ? 'SOPA'
        : producto.esPlatoSuelto
        ? 'SUELTO'
        : 'NORMAL';
    // Precio del completo: fijo del menú si existe; si no, plato + sopa.
    final precioCompleto = completo
        ? (precioAlmuerzo ?? (producto.precio + sopa!.precio))
        : 0.0;
    final nuevaLinea = CartLine(
      productoId: producto.productoId,
      menuDiaItemId: producto.menuDiaItemId,
      nombre: producto.nombre,
      precio: completo ? precioCompleto : producto.precio,
      cantidad: 1,
      tipo: producto.tipo,
      aplicaRecargoParaLlevar: _aplicaRecargoParaLlevar(
        producto.categoriaNombre,
      ),
      modalidadVenta: modalidad,
      productoSopaId: completo ? sopa!.productoId : null,
      menuDiaSopaItemId: completo ? sopa!.menuDiaItemId : null,
      nombreSopa: completo ? sopa!.nombre : null,
      precioSopaUnitario: completo ? sopa!.precio : 0,
      costoSopaUnitario: completo ? sopa!.costoUnitario : 0,
      tipoSopa: completo ? sopa!.tipo : null,
    );
    setState(() {
      final line = _cart[nuevaLinea.key];
      if (line == null) {
        _cart[nuevaLinea.key] = nuevaLinea;
      } else {
        _cart[nuevaLinea.key] = line.copyWith(cantidad: line.cantidad + 1);
      }
    });
  }

  void _changeQty(String key, double delta) {
    setState(() {
      final line = _cart[key];
      if (line == null) return;
      final nueva = line.cantidad + delta;
      if (nueva <= 0) {
        _cart.remove(key);
      } else {
        _cart[key] = line.copyWith(cantidad: nueva);
      }
    });
  }

  Future<void> _elegirPresentacion(_SaleProduct producto) async {
    if (!producto.vendible) {
      showAppMessage(
        context,
        producto.motivo ?? 'El producto no está disponible.',
        error: true,
      );
      return;
    }
    final elegida = await showModalBottomSheet<ProductoPresentacion>(
      context: context,
      builder: (context) => _PresentacionPicker(producto: producto),
    );
    if (elegida == null || !mounted) return;
    _addPresentacion(producto, elegida);
  }

  void _addPresentacion(
    _SaleProduct producto,
    ProductoPresentacion presentacion,
  ) {
    final nuevaLinea = CartLine(
      productoId: producto.productoId,
      menuDiaItemId: producto.menuDiaItemId,
      nombre: '${producto.nombre} · ${presentacion.nombre}',
      precio: presentacion.precio,
      cantidad: 1,
      tipo: producto.tipo,
      modalidadVenta: 'NORMAL',
      presentacionId: presentacion.id,
      aplicaRecargoParaLlevar: _aplicaRecargoParaLlevar(
        producto.categoriaNombre,
      ),
    );
    setState(() {
      final line = _cart[nuevaLinea.key];
      if (line == null) {
        _cart[nuevaLinea.key] = nuevaLinea;
      } else {
        _cart[nuevaLinea.key] = line.copyWith(cantidad: line.cantidad + 1);
      }
    });
  }

  void _remove(String key) {
    setState(() => _cart.remove(key));
  }

  void _limpiarCarrito() {
    setState(() {
      _cart.clear();
      _paraLlevar = false;
      _referencia.clear();
      _observacion.clear();
    });
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
      final pedidoId = await _salesRepository.crearPedido(
        usuarioId: widget.usuario.id,
        cajaId: caja.id,
        menuDiaId: data.menu?.habilitado == true ? data.menu!.id : null,
        referencia: _referencia.text,
        observacion: _observacion.text,
        lineas: lineasConRecargoParaLlevar(
          _cart.values,
          paraLlevar: _paraLlevar,
        ),
        pagos: pagos,
      );
      final detalle = await _salesRepository.getPedido(pedidoId);
      if (!mounted) return;
      _limpiarCarrito();
      setState(() {
        _saving = false;
        _reload();
      });
      showAppMessage(
        context,
        'Venta registrada por ${formatMoney(_totalAnterior(pagos))}.',
      );
      await _ofrecerImprimir(detalle);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, '$error', error: true);
    }
  }

  double _totalAnterior(List<PagoInput> pagos) =>
      pagos.fold<double>(0, (sum, pago) => sum + pago.monto);

  Future<void> _ofrecerImprimir(PedidoDetalle detalle) async {
    final imprimir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fichas del pedido'),
        content: Text(
          '¿Deseas imprimir las dos fichas del pedido #${detalle.pedido.id}? '
          'La primera es para el cliente y la segunda para el vendedor.',
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
    final printer = PrinterService();
    while (true) {
      _mostrarEnviandoImpresora();
      try {
        await printer.imprimirNotaVentaConfigurada(
          detalle: detalle,
          cajero: widget.usuario.nombre,
        );
        _cerrarProgreso();
        return;
      } catch (error) {
        _cerrarProgreso();
        if (!mounted) return;
        final reintentar = await _preguntarFalloImpresora('$error');
        if (!reintentar) return;
      }
    }
  }

  Future<bool> _preguntarFalloImpresora(String error) async {
    final accion = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No se pudo terminar la impresión'),
        content: Text(
          'Verifica que la impresora esté encendida, vinculada y guardada en '
          'la pantalla Impresora. Si la primera ficha ya salió, no reintentes '
          'para no duplicarla.\n\nDetalle: $error',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
    return accion == true;
  }

  void _mostrarEnviandoImpresora() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('Enviando a la impresora…')),
            ],
          ),
        ),
      ),
    );
  }

  void _cerrarProgreso() {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  /// Marca o rehabilita un producto. El cambio se guarda en `productos` y,
  /// si está en el menú de hoy, también en `menu_dia_items`; Ventas y Menú
  /// leen esos dos lugares.
  Future<void> _cambiarAgotado(_SaleProduct producto, bool agotado) async {
    if (agotado) {
      final confirmado = await confirmAction(
        context,
        title: 'Marcar como agotado',
        message:
            '${producto.nombre} dejará de mostrarse para la venta de hoy. '
            'Podrás rehabilitarlo desde el Menú del día.',
        confirmLabel: 'Marcar agotado',
        destructive: true,
      );
      if (!confirmado) return;
    }
    await _catalogRepository.setProductoAgotado(producto.productoId, agotado);
    final menuItemId = producto.menuDiaItemId;
    if (menuItemId != null) {
      await _menuRepository.setDisponible(
        menuItemId,
        !agotado,
        motivo: agotado ? 'Agotado' : null,
      );
    }
    if (!mounted) return;
    setState(_reload);
    showAppMessage(
      context,
      agotado
          ? '${producto.nombre} marcado como agotado.'
          : '${producto.nombre} habilitado de nuevo.',
    );
  }

  Widget _historialVentas(BuildContext context, _SalesData data) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ventas del día',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${data.pedidos.length} pedido(s)',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (data.pedidos.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Aún no hay ventas',
              message: 'Las ventas de hoy aparecerán aquí.',
            )
          else
            ...data.pedidos.map(
              (pedido) => _VentaTile(
                key: ValueKey(
                  '${pedido.id}-${pedido.estadoPago}-${pedido.total}',
                ),
                pedido: pedido,
                puedeAnular:
                    widget.usuario.puede(Permiso.ventas) && !pedido.anulado,
                onAnular: () => _anularVenta(pedido),
                onVerDetalle: () => _verDetalleVenta(pedido),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _verDetalleVenta(Pedido pedido) async {
    try {
      final detalle = await _salesRepository.getPedido(pedido.id);
      final devoluciones = await _salesRepository.getDevolucionesPedido(
        pedido.id,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) =>
            _VentaDetalleDialog(detalle: detalle, devoluciones: devoluciones),
      );
    } catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        'No se pudo cargar el detalle: $error',
        error: true,
      );
    }
  }

  Future<void> _anularVenta(Pedido pedido) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => _AnularVentaDialog(pedido: pedido),
    );
    if (motivo == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await _salesRepository.anularPedido(
        pedido.id,
        usuarioId: widget.usuario.id,
        motivo: motivo,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _reload();
      });
      showAppMessage(context, 'Venta #${pedido.id} anulada.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(
        context,
        'No se pudo anular la venta: $error',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SalesData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return LayoutBuilder(
          builder: (context, constraints) {
            final ancho = constraints.maxWidth >= 860;
            if (ancho &&
                data != null &&
                !snapshot.hasError &&
                data.caja != null) {
              const padding = 24.0;
              final pedidoWidth = constraints.maxWidth * 0.25;
              return Padding(
                padding: const EdgeInsets.all(padding),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _encabezadoVentas(),
                            _estadoMenu(context, data),
                            const SizedBox(height: 14),
                            _filtros(context, data),
                            const SizedBox(height: 14),
                            _catalogo(context, data),
                            const SizedBox(height: 16),
                            _historialVentas(context, data),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: pedidoWidth,
                      height: constraints.maxHeight - padding * 2,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _carrito(context, data),
                            const SizedBox(height: 16),
                            _productosAgotados(context, data),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return SingleChildScrollView(
              padding: EdgeInsets.all(
                esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _encabezadoVentas(),
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
                    )
                  else ...[
                    _estadoMenu(context, data),
                    const SizedBox(height: 14),
                    _filtros(context, data),
                    const SizedBox(height: 14),
                    _catalogo(context, data),
                    const SizedBox(height: 16),
                    _carrito(context, data),
                    const SizedBox(height: 16),
                    _historialVentas(context, data),
                    const SizedBox(height: 16),
                    _productosAgotados(context, data),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _encabezadoVentas() => PageHeader(
    title: 'Ventas',
    subtitle: 'Toca el producto para agregarlo al pedido. Solo se venden los del menú habilitado.',
    actions: [
      OutlinedButton.icon(
        onPressed: () => setState(_reload),
        icon: const Icon(Icons.refresh),
        label: const Text('Actualizar'),
      ),
    ],
  );

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

  /// Categorías con productos en el catálogo, en el orden canónico de la base
  /// (PLATOS SUELTOS, SOPAS, BEBIDAS CALIENTES, REFRESCOS, FRAPPES, COMBOS,
  /// VENTA DIRECTA y las que cree el usuario) y con el color de la categoría.
  List<CategoriaProducto> _categoriasDelCatalogo(_SalesData data) {
    final presentes = <String, _SaleProduct>{};
    for (final producto in data.productos) {
      presentes.putIfAbsent(
        producto.categoriaNombre.trim().toUpperCase(),
        () => producto,
      );
    }
    final resultado = <CategoriaProducto>[];
    final vistas = <String>{};
    for (final categoria in data.categorias) {
      final clave = categoria.nombre.trim().toUpperCase();
      if (!presentes.containsKey(clave) || !vistas.add(clave)) continue;
      resultado.add(categoria);
    }
    // Categorías de productos sin registro en la lista (no debería pasar).
    for (final entrada in presentes.entries) {
      if (!vistas.add(entrada.key)) continue;
      resultado.add(
        CategoriaProducto(
          nombre: entrada.value.categoriaNombre,
          color: entrada.value.categoriaColor,
          siempreDisponible: false,
          orden: 1000,
          activo: true,
        ),
      );
    }
    return resultado;
  }

  void _seleccionarCategoria(String? categoria) {
    setState(() => _categoria = categoria);
    // La franja es deslizable: se lleva el chip elegido a la vista.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = categoria == null
          ? _chipTodasKey
          : _chipKeys.putIfAbsent(categoria, () => GlobalKey());
      final contexto = key.currentContext;
      if (contexto != null) {
        Scrollable.ensureVisible(
          contexto,
          duration: const Duration(milliseconds: 250),
          alignment: 0.5,
        );
      }
    });
  }

  Widget _filtros(BuildContext context, _SalesData data) {
    final categorias = _categoriasDelCatalogo(data);
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 10),
          // Franja deslizable sin barra de scroll visible: se desliza con el
          // dedo o el ratón sin mostrar el indicador.
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    key: _chipTodasKey,
                    label: const Text('Todas'),
                    selected: _categoria == null,
                    onSelected: (_) => _seleccionarCategoria(null),
                  ),
                  for (final categoria in categorias) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      key: _chipKeys.putIfAbsent(
                        categoria.nombre,
                        () => GlobalKey(),
                      ),
                      avatar: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Color(categoria.color),
                          shape: BoxShape.circle,
                        ),
                      ),
                      label: Text(categoria.nombre),
                      selected: _categoria == categoria.nombre,
                      onSelected: (_) => _seleccionarCategoria(categoria.nombre),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_SaleProduct> _productosFiltrados(_SalesData data) {
    final term = _search.trim().toLowerCase();
    return data.productos.where((producto) {
      if (_categoria != null &&
          producto.categoriaNombre.trim().toUpperCase() !=
              _categoria!.trim().toUpperCase()) {
        return false;
      }
      return term.isEmpty || producto.nombre.toLowerCase().contains(term);
    }).toList();
  }

  Widget _catalogo(BuildContext context, _SalesData data) {
    final filtrados = _productosFiltrados(data);
    if (filtrados.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'No hay productos disponibles',
        message: 'Crea productos activos en Productos y publícalos en el Menú del día.',
      );
    }

    final vendibles = filtrados.where((producto) => producto.vendible).toList();
    if (vendibles.isEmpty) {
      return const EmptyState(
        icon: Icons.no_food_outlined,
        title: 'No hay productos disponibles',
        message: 'Revisa el menú del día o rehabilita un producto agotado.',
      );
    }
    return _gridProductos(context, data, vendibles);
  }

  /// Sección de agotados/fuera del menú, separada del catálogo para poder
  /// colocarla debajo del pedido en tablet.
  Widget _productosAgotados(BuildContext context, _SalesData data) {
    final noDisponibles = _productosFiltrados(data)
        .where((producto) => !producto.vendible)
        .toList();
    if (noDisponibles.isEmpty) return const SizedBox.shrink();
    return _fueraDelMenu(context, data, noDisponibles);
  }

  Widget _gridProductos(
    BuildContext context,
    _SalesData data,
    List<_SaleProduct> productos,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620
            ? 3
            : constraints.maxWidth >= 380
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: productos.map((producto) {
            final cantidad = _cart.values
                .where((linea) => linea.productoId == producto.productoId)
                .fold<double>(0, (suma, linea) => suma + linea.cantidad)
                .round();
            final sopa = data.sopaDelDia;
            final ofreceModalidad =
                producto.menuDiaItemId != null &&
                producto.esPlatoSuelto &&
                sopa != null;
            final precioCompleto = sopa != null
                ? (data.precioAlmuerzo ?? (producto.precio + sopa.precio))
                : producto.precio;
            final tienePresentaciones = producto.presentaciones.isNotEmpty;
            final precioMostrado = tienePresentaciones
                ? producto.presentaciones
                      .map((presentacion) => presentacion.precio)
                      .reduce((a, b) => a < b ? a : b)
                : producto.precio;
            final pie = ofreceModalidad
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: producto.vendible
                              ? () => _add(producto)
                              : null,
                          child: Text(
                            'Suelto · ${formatMoney(producto.precio)}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: producto.vendible && sopa.vendible
                              ? () => _add(
                                  producto,
                                  completo: true,
                                  sopa: sopa,
                                  precioAlmuerzo: data.precioAlmuerzo,
                                )
                              : null,
                          child: Text(
                            'Completo · ${formatMoney(precioCompleto)}',
                          ),
                        ),
                      ),
                    ],
                  )
                : null;
            return SizedBox(
              width: width,
              child: ProductoCatalogoCard(
                nombre: producto.nombre,
                categoria: producto.categoriaEtiqueta,
                precio: precioMostrado,
                color: producto.categoriaColor,
                imagen: producto.imagen,
                esDirecto: producto.esDirecto,
                stock: producto.stock,
                habilitado: producto.vendible,
                mensaje: producto.vendible
                    ? (tienePresentaciones
                          ? (cantidad > 0
                                ? '$cantidad en el pedido'
                                : 'Elige presentación')
                          : (ofreceModalidad
                                ? (cantidad > 0
                                      ? '$cantidad en el pedido'
                                      : 'Elige cómo se sirve')
                                : (cantidad > 0
                                      ? 'Toca para agregar · $cantidad en el pedido'
                                      : 'Toca para agregar')))
                    : producto.razon,
                onTap: tienePresentaciones
                    ? (producto.vendible
                          ? () => _elegirPresentacion(producto)
                          : null)
                    : ofreceModalidad
                    ? null
                    : producto.vendible
                    ? () => _add(producto)
                    : null,
                pie: pie,
                advertencia: producto.vendible ? producto.advertencia : null,
                agotado:
                    producto.agotado ||
                    (producto.enMenu && !producto.disponible),
                accion:
                    producto.enMenu && widget.usuario.puede(Permiso.agotamiento)
                    ? Tooltip(
                        message: producto.agotado || !producto.disponible
                            ? 'Rehabilitar producto'
                            : 'Marcar como agotado',
                        child: Transform.scale(
                          scale: 0.8,
                          child: Switch(
                            value: !producto.agotado && producto.disponible,
                            onChanged: (value) =>
                                _cambiarAgotado(producto, !value),
                          ),
                        ),
                      )
                    : null,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// Sección colapsable con los productos activos que no se eligieron para el
  /// menú de hoy. No se pueden vender y quedan ocultos por defecto.
  Widget _fueraDelMenu(
    BuildContext context,
    _SalesData data,
    List<_SaleProduct> productos,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            leading: Icon(
              Icons.visibility_off_outlined,
              color: scheme.onSurfaceVariant,
            ),
            title: const Text(
              'Productos agotados o fuera del menú',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${productos.length} producto(s) no disponible(s) para vender hoy.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            trailing: Icon(
              _mostrarFueraMenu ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () => setState(() => _mostrarFueraMenu = !_mostrarFueraMenu),
          ),
          if (_mostrarFueraMenu)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _gridProductos(context, data, productos),
            ),
        ],
      ),
    );
  }

  Widget _carrito(BuildContext context, _SalesData data) {
    final scheme = Theme.of(context).colorScheme;
    final tieneProductosParaLlevar = _cart.values.any(
      (linea) => linea.aplicaRecargoParaLlevar,
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final titulo = Text(
                'Pedido',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              );
              final cantidad = Text(
                '$_unidades ítem(s)',
                style: TextStyle(color: scheme.onSurfaceVariant),
              );
              if (constraints.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        titulo,
                      ],
                    ),
                    Align(alignment: Alignment.centerRight, child: cantidad),
                  ],
                );
              }
              return Row(
                children: [
                  Icon(Icons.shopping_cart_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  titulo,
                  const Spacer(),
                  cantidad,
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (_cart.isEmpty)
            const EmptyState(
              icon: Icons.add_shopping_cart,
              title: 'Carrito vacío',
              message: 'Toca un producto para agregarlo al pedido.',
            )
          else ...[
            if (tieneProductosParaLlevar)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Para llevar'),
                subtitle: const Text('+ Bs 0,50 por pedido'),
                value: _paraLlevar,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _paraLlevar = value),
              ),
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
                          line.modalidadVenta == 'COMPLETO'
                              ? '${line.nombre} completo'
                              : line.nombre,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (line.modalidadVenta == 'COMPLETO' &&
                            line.nombreSopa != null)
                          Text(
                            'Incluye ${line.nombreSopa} · '
                            '${formatMoney(line.precioSopaUnitario)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
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
                          onPressed: () => _changeQty(line.key, -1),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          formatQty(line.cantidad),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _changeQty(line.key, 1),
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
                      onPressed: () => _remove(line.key),
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
            if (_paraLlevar && tieneProductosParaLlevar)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Text('Recargo para llevar'),
                    const Spacer(),
                    Text(formatMoney(recargoParaLlevarPorPedido)),
                  ],
                ),
              ),
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
            FilledButton.icon(
              onPressed: _saving ? null : () => _cobrar(data),
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Pagado'),
            ),
          ],
        ],
      ),
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

  bool get _montosValidos =>
      (_efectivo.text.trim().isEmpty ||
          validateDecimalAmount(_efectivo.text) == null) &&
      (_qr.text.trim().isEmpty || validateDecimalAmount(_qr.text) == null);

  bool get _completo => _montosValidos && _suma > 0 && _restante.abs() <= 0.05;

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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text('Total a cobrar'),
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
                inputFormatters: [decimalAmountInputFormatter],
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
                inputFormatters: [decimalAmountInputFormatter],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: appInput(label: 'QR (Bs)', icon: Icons.qr_code_2),
                onChanged: (value) => _actualizar('QR', value),
              ),
              const SizedBox(height: 8),
              if (!_montosValidos)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Ingresa montos numéricos válidos, sin negativos.',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
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
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 4,
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

class _PresentacionPicker extends StatelessWidget {
  const _PresentacionPicker({required this.producto});

  final _SaleProduct producto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget miniatura(ProductoPresentacion presentacion) {
      final bytes = presentacion.imagen ?? producto.imagen;
      if (bytes != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      }
      return Icon(Icons.local_drink_outlined, color: scheme.primary);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              producto.nombre,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Elige la presentación',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: producto.presentaciones
                    .map(
                      (presentacion) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: miniatura(presentacion),
                        title: Text(presentacion.nombre),
                        trailing: Text(
                          formatMoney(presentacion.precio),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: () => Navigator.pop(context, presentacion),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila del historial de ventas del día. El detalle se abre con el botón de ojo.
class _VentaTile extends StatelessWidget {
  const _VentaTile({
    super.key,
    required this.pedido,
    required this.puedeAnular,
    required this.onAnular,
    required this.onVerDetalle,
  });

  final Pedido pedido;
  final bool puedeAnular;
  final VoidCallback onAnular;
  final VoidCallback onVerDetalle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final anulada = pedido.anulado;
    final fecha = parseSqlDateTime(pedido.fecha);
    final hora = fecha == null ? pedido.fecha : formatTimeShort(fecha);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: anulada ? scheme.errorContainer.withValues(alpha: 0.18) : null,
        border: Border.all(
          color: anulada
              ? scheme.error.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.7),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 20,
              color: anulada ? scheme.error : scheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '#${pedido.id}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (anulada) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.error,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'ANULADA',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: scheme.onError,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$hora · ${pedido.usuarioNombre}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMoney(pedido.total),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (puedeAnular)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.error,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 28),
                    ),
                    onPressed: onAnular,
                    child: const Text('ANULAR'),
                  )
                else
                  Text(
                    anulada ? 'Anulada' : 'Pagada',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
            IconButton(
              tooltip: 'Ver detalle',
              onPressed: onVerDetalle,
              icon: const Icon(Icons.visibility_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detalle de una venta en un emergente, abierto desde el botón de ojo.
class _VentaDetalleDialog extends StatelessWidget {
  const _VentaDetalleDialog({
    required this.detalle,
    required this.devoluciones,
  });

  final PedidoDetalle detalle;
  final List<Devolucion> devoluciones;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineas = detalle.lineas
        .where((linea) => !linea.esComponente)
        .toList();
    final motivo = devoluciones
        .map((devolucion) => devolucion.motivo ?? '')
        .firstWhere((texto) => texto.isNotEmpty, orElse: () => '');
    final pedido = detalle.pedido;
    final fecha = parseSqlDateTime(pedido.fecha);
    final fechaTexto = fecha == null
        ? pedido.fecha
        : formatDateTimeShort(fecha);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      title: Text('Pedido #${pedido.id}${pedido.anulado ? ' · ANULADA' : ''}'),
      content: DialogSurface(
        maxWidth: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                fechaTexto,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const Divider(height: 18),
              ...lineas.map(
                (linea) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${formatQty(linea.cantidad)} x ${linea.nombre}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (linea.modalidadVenta == 'COMPLETO' &&
                                linea.nombreSopa != null)
                              Text(
                                'Incluye ${linea.nombreSopa}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                      Text(formatMoney(linea.subtotal)),
                    ],
                  ),
                ),
              ),
              const Divider(height: 16),
              Row(
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    formatMoney(pedido.total),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Pagos',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              ...detalle.pagos.map(
                (pago) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        pago.metodo == 'EFECTIVO' ? 'Efectivo' : 'QR',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Text(
                        formatMoney(pago.monto),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        pago.estado == 'ANULADO' ? 'Anulado' : 'Confirmado',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: pago.estado == 'ANULADO'
                              ? scheme.error
                              : scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (devoluciones.isNotEmpty) ...[
                const Divider(height: 16),
                Text(
                  'Devolución registrada',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.error,
                  ),
                ),
                ...devoluciones.map(
                  (devolucion) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text(
                          '${devolucion.metodo == 'EFECTIVO' ? 'Efectivo' : 'QR'}'
                          '${(devolucion.usuarioNombre ?? '').isEmpty ? '' : ' · ${devolucion.usuarioNombre}'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Spacer(),
                        Text(
                          formatMoney(devolucion.monto),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.error),
                        ),
                      ],
                    ),
                  ),
                ),
                if (motivo.isNotEmpty)
                  Text(
                    'Motivo: $motivo',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

/// Diálogo de anulación. El controlador y el formulario viven en el Estado
/// del diálogo para no disponerlos mientras la ruta todavía se está cerrando.
class _AnularVentaDialog extends StatefulWidget {
  const _AnularVentaDialog({required this.pedido});

  final Pedido pedido;

  @override
  State<_AnularVentaDialog> createState() => _AnularVentaDialogState();
}

class _AnularVentaDialogState extends State<_AnularVentaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      scrollable: true,
      title: Text('Anular venta #${widget.pedido.id}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Se anulará el pedido #${widget.pedido.id} por '
              '${formatMoney(widget.pedido.total)}. La venta y su anulación '
              'quedarán registradas en el historial.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _motivo,
              autofocus: true,
              maxLines: 3,
              decoration: appInput(label: 'Motivo (obligatorio)'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Ingresa el motivo de la anulación'
                  : null,
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
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, _motivo.text.trim());
          },
          child: const Text('Anular venta'),
        ),
      ],
    );
  }
}
