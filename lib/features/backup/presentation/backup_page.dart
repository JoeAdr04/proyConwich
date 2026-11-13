import 'package:flutter/material.dart';

import '../../../core/backup/backup_service.dart';
import '../../../core/backup/drive_backup_service.dart';
import '../../../core/backup/excel_exporter.dart';
import '../../../core/date_utils.dart';
import '../../../data/database/app_database.dart';
import '../../../ui/common.dart';

/// Pantalla de respaldo, restauración y exportación. Solo se abre desde el
/// menú del administrador.
///
/// Devuelve `true` por `Navigator.pop` cuando se restauró una copia, para que
/// el shell cierre la sesión: los usuarios del archivo restaurado pueden no
/// coincidir con el que estaba usando la app.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final _service = BackupService();
  final _excel = ExcelExporter();
  final _drive = DriveBackupService();

  Map<String, Object?>? _meta;
  DriveConfig? _driveConfig;
  List<CopiaSeguridad> _copias = const [];
  bool _cargando = true;
  bool _ocupado = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final meta = await _service.metaActual();
      final driveConfig = await _drive.leerConfig();
      final copias = _service.disponible
          ? await _service.listarCopiasSeguridad()
          : const <CopiaSeguridad>[];
      if (!mounted) return;
      setState(() {
        _meta = meta;
        _driveConfig = driveConfig;
        _copias = copias;
        _cargando = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = _mensajeError(error);
      });
    }
  }

  Future<void> _ejecutar(
    Future<void> Function() accion, {
    String? exito,
  }) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await accion();
      if (exito != null && mounted) showAppMessage(context, exito);
    } catch (error) {
      if (mounted) {
        showAppMessage(context, _mensajeError(error), error: true);
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Rect? _origenRect(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _compartirCopia() => _ejecutar(() async {
    final copia = await _service.crearCopia(motivo: 'manual');
    await _service.compartirCopia(copia);
    await _cargar();
  });

  Future<void> _guardarCopia() => _ejecutar(() async {
    final copia = await _service.crearCopia(motivo: 'manual');
    final guardado = await _service.guardarCopia(copia);
    if (!mounted) return;
    if (guardado) {
      showAppMessage(context, 'Copia guardada como ${copia.nombre}.');
    }
    await _cargar();
  });

  Future<void> _exportar({required bool compartir}) => _ejecutar(() async {
    final bytes = await _excel.generar();
    final nombre = _excel.nombreArchivo(DateTime.now());
    if (compartir) {
      if (!mounted) return;
      await _excel.compartir(
        bytes,
        nombre: nombre,
        origen: _origenRect(context),
      );
    } else {
      final guardado = await _excel.guardar(bytes, nombre: nombre);
      if (!mounted) return;
      if (guardado) {
        showAppMessage(context, 'Excel guardado como $nombre.');
      }
    }
  });

  Future<void> _elegirCarpetaDrive() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      final carpeta = await _drive.elegirCarpeta();
      if (!mounted) return;
      if (carpeta == null) {
        showAppMessage(context, 'No se eligió ninguna carpeta.');
      } else {
        showAppMessage(
          context,
          'Carpeta de Drive configurada: ${carpeta.nombre}.',
        );
      }
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      showAppMessage(context, _mensajeError(error), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _respaldarEnDrive() => _ejecutar(() async {
    await _drive.respaldarAhora(motivo: 'manual');
    await _cargar();
  }, exito: 'Copia guardada en Google Drive.');

  Future<void> _cambiarDriveHabilitado(bool value) async {
    await _drive.guardarConfig(habilitado: value);
    await _cargar();
  }

  Future<void> _cambiarAlCerrarCaja(bool value) async {
    await _drive.guardarConfig(alCerrarCaja: value);
    await _cargar();
  }

  Future<void> _cambiarFrecuencia(String? value) async {
    if (value == null) return;
    await _drive.guardarConfig(frecuencia: value);
    await _cargar();
  }

  Future<void> _editarRetencion() async {
    final actual = _driveConfig?.retencion ?? 30;
    final controller = TextEditingController(text: '$actual');
    final valor = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Copias a conservar'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: appInput(
            label: 'Cantidad de copias',
            hint: 'Entre 1 y 365',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (valor == null) return;
    await _drive.guardarConfig(retencion: valor.clamp(1, 365));
    await _cargar();
  }

  String _frecuenciaLabel(String value) => switch (value) {
    'CADA_CIERRE' => 'Cada cierre de caja',
    'DIARIO' => 'Una vez al día',
    'SEMANAL' => 'Una vez por semana',
    'MENSUAL' => 'Una vez al mes',
    _ => 'Solo manual',
  };

  Future<void> _restaurarDesdeArchivo() async {
    if (_ocupado) return;
    try {
      final elegido = await _service.elegirCopia();
      if (elegido == null || !mounted) return;
      setState(() => _ocupado = true);
      final inspeccion = await _service.inspeccionar(
        elegido.bytes,
        nombre: elegido.nombre,
      );
      if (!mounted) return;
      final confirmado = await _confirmarRestauracion(inspeccion);
      if (!confirmado) {
        setState(() => _ocupado = false);
        return;
      }
      await _aplicar(inspeccion);
    } catch (error) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      showAppMessage(context, _mensajeError(error), error: true);
    }
  }

  Future<void> _restaurarSeguridad(CopiaSeguridad copia) async {
    if (_ocupado) return;
    final confirmado = await confirmAction(
      context,
      title: 'Restaurar copia de seguridad',
      message:
          'Se reemplazará toda la información actual por la copia del '
          '${formatDateTimeShort(copia.fecha)}. Antes se guardará otra copia '
          'del estado actual.',
      confirmLabel: 'Restaurar',
      destructive: true,
    );
    if (!confirmado || !mounted) return;
    setState(() => _ocupado = true);
    try {
      final inspeccion = await _service.inspeccionar(
        await _service.leerArchivo(copia.ruta),
        nombre: copia.nombre,
        fechaArchivo: copia.fecha,
      );
      await _aplicar(inspeccion);
    } catch (error) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      showAppMessage(context, _mensajeError(error), error: true);
    }
  }

  Future<void> _aplicar(InspeccionCopia inspeccion) async {
    try {
      await _service.restaurar(inspeccion);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Copia restaurada'),
          content: const Text(
            'La información se restauró correctamente. Por seguridad se '
            'cerrará la sesión: ingresa con el usuario y la contraseña que '
            'existían en la copia.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      showAppMessage(context, _mensajeError(error), error: true);
    }
  }

  Future<bool> _confirmarRestauracion(InspeccionCopia inspeccion) async {
    final actual = _meta?['instalacion_id'] as String?;
    final otraInstalacion = !inspeccion.esMismaInstalacion(actual);
    final compatible = inspeccion.versionCompatible(AppDatabase.schemaVersion);
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final bloqueado = !compatible || !inspeccion.integridadOk;
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 20,
          ),
          title: const Text('Verificar copia'),
          content: DialogSurface(
            maxWidth: 470,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Dato('Archivo', inspeccion.nombreArchivo),
                  _Dato(
                    'Fecha del respaldo',
                    inspeccion.fechaRespaldo != null
                        ? formatDateTimeShort(inspeccion.fechaRespaldo!)
                        : inspeccion.fechaArchivo != null
                        ? '${formatDateTimeShort(inspeccion.fechaArchivo!)} '
                              '(fecha del archivo)'
                        : 'Desconocida',
                  ),
                  if (!inspeccion.tieneMetadata)
                    _Dato(
                      'Metadatos',
                      'Copia antigua, sin metadatos',
                      color: scheme.error,
                    ),
                  _Dato(
                    'Generada por',
                    inspeccion.appVersion == null
                        ? '—'
                        : 'Conwich ${inspeccion.appVersion}',
                  ),
                  _Dato(
                    'Esquema',
                    'v${inspeccion.schemaVersion} '
                        '(esta app: v${AppDatabase.schemaVersion})',
                    color: compatible ? null : scheme.error,
                  ),
                  _Dato(
                    'Integridad',
                    inspeccion.integridadOk
                        ? 'OK'
                        : 'Fallida (${inspeccion.integridadDetalle ?? '—'})',
                    color: inspeccion.integridadOk ? null : scheme.error,
                  ),
                  _Dato(
                    'Instalación',
                    inspeccion.instalacionId == null
                        ? '—'
                        : otraInstalacion
                        ? 'Proviene de otro dispositivo'
                        : 'Este dispositivo',
                    color: otraInstalacion ? scheme.error : null,
                  ),
                  _Dato(
                    'Contenido',
                    '${inspeccion.conteos['usuarios'] ?? 0} usuarios · '
                        '${inspeccion.conteos['productos'] ?? 0} productos · '
                        '${inspeccion.conteos['pedidos'] ?? 0} pedidos · '
                        '${inspeccion.conteos['gastos'] ?? 0} gastos',
                  ),
                  _Dato('Tamaño', _tamano(inspeccion.tamanoBytes)),
                  _Dato('SHA-256', inspeccion.sha256),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      bloqueado
                          ? 'Esta copia no se puede restaurar en esta versión de '
                                'la app.'
                          : 'Se reemplazará TODA la información actual (ventas, '
                                'productos, usuarios y caja). Antes se guardará '
                                'automáticamente una copia de seguridad.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: bloqueado ? null : () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              child: const Text('Restaurar'),
            ),
          ],
        );
      },
    );
    return resultado ?? false;
  }

  Widget _driveCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final config = _driveConfig;
    final configurado = config?.configurado == true;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Respaldo automático en Google Drive',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (config != null)
                Switch(
                  value: config.habilitado,
                  onChanged: _ocupado ? null : _cambiarDriveHabilitado,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Elige una carpeta de Drive desde el selector de Android. Cada '
            'copia se guarda ahí sin cuentas de Google Cloud ni suscripciones.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (!_drive.disponible)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'El respaldo en Drive solo está disponible en la app instalada '
                'en Android.',
                style: TextStyle(color: scheme.error),
              ),
            )
          else ...[
            const SizedBox(height: 12),
            _Dato(
              'Carpeta',
              config?.carpetaNombre?.isNotEmpty == true
                  ? config!.carpetaNombre!
                  : 'Sin elegir',
            ),
            _Dato(
              'Estado',
              configurado
                  ? (config!.habilitado ? 'Activo' : 'Desactivado')
                  : 'Falta elegir carpeta',
            ),
            _Dato(
              'Último respaldo',
              config?.ultimoExito == null
                  ? 'Todavía no se guardó ninguno'
                  : formatDateTimeShort(config!.ultimoExito!),
            ),
            if (config?.ultimoError != null)
              _Dato('Último error', config!.ultimoError!, color: scheme.error),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : _elegirCarpetaDrive,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(
                    configurado ? 'Cambiar carpeta' : 'Elegir carpeta de Drive',
                  ),
                ),
                if (configurado)
                  FilledButton.icon(
                    onPressed: _ocupado ? null : _respaldarEnDrive,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Respaldar ahora'),
                  ),
              ],
            ),
            if (configurado) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Respaldar al cerrar caja'),
                subtitle: const Text(
                  'La copia se sube en segundo plano sin bloquear el cierre.',
                ),
                value: config?.alCerrarCaja ?? true,
                onChanged: _ocupado ? null : _cambiarAlCerrarCaja,
              ),
              DropdownButtonFormField<String>(
                initialValue: config?.frecuencia ?? 'CADA_CIERRE',
                isExpanded: true,
                decoration: appInput(
                  label: 'Frecuencia de respaldo automático',
                ),
                items: DriveBackupService.frecuencias
                    .map(
                      (frecuencia) => DropdownMenuItem(
                        value: frecuencia,
                        child: Text(_frecuenciaLabel(frecuencia)),
                      ),
                    )
                    .toList(),
                onChanged: _ocupado ? null : _cambiarFrecuencia,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history_toggle_off),
                title: const Text('Copias a conservar'),
                subtitle: Text(
                  '${config?.retencion ?? 30} copia(s) más recientes',
                ),
                trailing: TextButton(
                  onPressed: _ocupado ? null : _editarRetencion,
                  child: const Text('Cambiar'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final id = _meta?['instalacion_id'] as String?;
    final ultimo = parseSqlDateTime(_meta?['ultimo_respaldo_en'] as String?);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Respaldo y restauración'),
        backgroundColor: const Color(0xFF3D2419), // Espresso
        surfaceTintColor: const Color(0xFF3D2419),
      ),
      body: _cargando
          ? const LoadingView()
          : ListView(
              padding: EdgeInsets.all(
                esAngosto(MediaQuery.sizeOf(context).width) ? 12 : 24,
              ),
              children: [
                PageHeader(
                  title: 'Tus datos, bajo tu control',
                  subtitle:
                      'La información vive en este dispositivo. Genera una '
                      'copia para guardarla o compartirla, y restáurala si '
                      'cambias de equipo.',
                  actions: [
                    OutlinedButton.icon(
                      onPressed: _ocupado ? null : _cargar,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualizar'),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  AppCard(
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
                  const SizedBox(height: 16),
                ],
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.storage_outlined, color: scheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Respaldo completo (.db)',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Copia exacta y restaurable. Incluye ventas, '
                        'inventario y usuarios.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      _Dato(
                        'Última copia',
                        ultimo == null
                            ? 'Todavía no se generó ninguna'
                            : formatDateTimeShort(ultimo),
                      ),
                      _Dato('Instalación', id == null || id.isEmpty ? '—' : id),
                      const SizedBox(height: 12),
                      if (!_service.disponible)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(
                              alpha: 0.4,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'En el navegador no se puede copiar el archivo de '
                            'la base. Puedes exportar a Excel o abrir la app '
                            'instalada para respaldar y restaurar.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.primary),
                          ),
                        ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _ocupado || !_service.disponible
                                ? null
                                : _compartirCopia,
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Compartir copia'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _ocupado || !_service.disponible
                                ? null
                                : _guardarCopia,
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Guardar en el dispositivo'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _driveCard(context),
                const SizedBox(height: 16),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.restore_page_outlined,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Restaurar una copia',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Antes de aplicar nada se muestra la fecha, la versión '
                        'y el contenido del archivo.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _ocupado || !_service.disponible
                            ? null
                            : _restaurarDesdeArchivo,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Seleccionar copia…'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.table_view_outlined,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Exportar a Excel',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Un archivo con una hoja por tabla para revisar o '
                        'llevar a contabilidad. No sirve para restaurar.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _ocupado
                                ? null
                                : () => _exportar(compartir: true),
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Compartir Excel'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _ocupado
                                ? null
                                : () => _exportar(compartir: false),
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Guardar Excel'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.history_outlined, color: scheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Copias de seguridad automáticas',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Se guardan antes de cada restauración. Se conservan '
                        'las 5 más recientes.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      if (_copias.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('Todavía no hay copias de seguridad.'),
                        )
                      else
                        for (final copia in _copias)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.save_outlined),
                            title: Text(formatDateTimeShort(copia.fecha)),
                            subtitle: Text(
                              '${copia.motivo ?? 'Copia de seguridad'} · '
                              '${_tamano(copia.tamanoBytes)}',
                            ),
                            trailing: TextButton(
                              onPressed: _ocupado
                                  ? null
                                  : () => _restaurarSeguridad(copia),
                              child: const Text('Restaurar'),
                            ),
                          ),
                    ],
                  ),
                ),
                if (_ocupado)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor, {this.color});

  final String etiqueta;
  final String valor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              etiqueta,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

String _tamano(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String _mensajeError(Object error) {
  if (error is FormatException) return error.message;
  if (error is StateError) return error.message;
  if (error is UnsupportedError) return error.message ?? '$error';
  return '$error';
}
