import 'package:flutter/material.dart';

import '../../../core/auth_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

/// Primer acceso obligatorio: reemplaza las credenciales por defecto
/// (`admin` / `1234`) antes de permitir el uso de la aplicación.
///
/// No se puede omitir ni volver atrás; la única salida es cerrar sesión, y en
/// el siguiente inicio de sesión se vuelve a pedir.
class OnboardingAdminPage extends StatefulWidget {
  const OnboardingAdminPage({
    super.key,
    required this.usuario,
    required this.onCompletado,
    required this.onLogout,
  });

  final Usuario usuario;
  final ValueChanged<Usuario> onCompletado;
  final VoidCallback onLogout;

  @override
  State<OnboardingAdminPage> createState() => _OnboardingAdminPageState();
}

class _OnboardingAdminPageState extends State<OnboardingAdminPage> {
  static const int _minPassword = 8;
  static const _clavesDebiles = <String>{
    '1234',
    '12345678',
    'admin',
    'admin123',
    'sazon123',
    'password',
  };

  final _formKey = GlobalKey<FormState>();
  final _repository = AuthRepository();
  final _usuario = TextEditingController();
  final _password = TextEditingController();
  final _confirmar = TextEditingController();
  bool _saving = false;
  bool _verPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Se sugiere un nombre distinto al de fábrica para que el administrador
    // solo tenga que ajustarlo si lo desea.
    _usuario.text = '';
  }

  @override
  void dispose() {
    _usuario.dispose();
    _password.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  String? _validarUsuario(String? value) {
    final texto = value?.trim() ?? '';
    if (texto.isEmpty) return 'Ingresa un usuario';
    if (texto.length < 3) return 'Usa al menos 3 caracteres';
    if (texto.contains(' ')) return 'Sin espacios';
    if (texto.toLowerCase() == 'admin') {
      return 'Elige un usuario distinto de «admin»';
    }
    return null;
  }

  String? _validarPassword(String? value) {
    final texto = value ?? '';
    if (texto.isEmpty) return 'Ingresa una contraseña';
    if (texto.length < _minPassword) {
      return 'Usa al menos $_minPassword caracteres';
    }
    if (_clavesDebiles.contains(texto.toLowerCase())) {
      return 'Esa contraseña es demasiado fácil de adivinar';
    }
    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final nuevoUsuario = _usuario.text.trim();
      final disponible = await _repository.usuarioDisponible(
        nuevoUsuario,
        exceptoId: widget.usuario.id,
      );
      if (!disponible) {
        if (!mounted) return;
        setState(() {
          _error = 'Ese usuario ya está en uso. Elige otro.';
          _saving = false;
        });
        return;
      }
      await _repository.actualizarCredenciales(
        usuarioId: widget.usuario.id,
        usuario: nuevoUsuario,
        password: _password.text,
      );
      if (!mounted) return;
      widget.onCompletado(
        widget.usuario.copyWith(
          usuario: nuevoUsuario,
          debeCambiarPassword: false,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron guardar los datos: $error';
        _saving = false;
      });
    }
  }

  Future<void> _salir() async {
    final confirmado = await confirmAction(
      context,
      title: 'Cerrar sesión',
      message:
          'Todavía no defines tu usuario y contraseña. En el próximo inicio '
          'de sesión se volverá a pedir.',
      confirmLabel: 'Cerrar sesión',
    );
    if (confirmado && mounted) widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.primary.withValues(alpha: 0.12),
                Theme.of(context).scaffoldBackgroundColor,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 470),
                  child: AppCard(
                    padding: const EdgeInsets.all(28),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: const Icon(
                                  Icons.shield_outlined,
                                  color: Color(0xFF2B1A12), // Texto oscuro
                                  size: 27,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Primer acceso',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    Text(
                                      'Personaliza tus credenciales',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(
                                alpha: 0.4,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Estás usando el usuario y la contraseña '
                                    'de fábrica. Define unos propios para '
                                    'continuar.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: scheme.primary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _usuario,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newUsername],
                            decoration: appInput(
                              label: 'Nuevo usuario',
                              icon: Icons.person_outline,
                            ),
                            validator: _validarUsuario,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            obscureText: !_verPassword,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: appInput(
                              label: 'Nueva contraseña',
                              icon: Icons.lock_outline,
                              suffix: IconButton(
                                tooltip: _verPassword
                                    ? 'Ocultar contraseña'
                                    : 'Mostrar contraseña',
                                onPressed: () => setState(
                                  () => _verPassword = !_verPassword,
                                ),
                                icon: Icon(
                                  _verPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            validator: _validarPassword,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmar,
                            obscureText: !_verPassword,
                            onFieldSubmitted: (_) => _guardar(),
                            decoration: appInput(
                              label: 'Repetir contraseña',
                              icon: Icons.lock_reset_outlined,
                            ),
                            validator: (value) => value != _password.text
                                ? 'Las contraseñas no coinciden'
                                : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _error!,
                              style: TextStyle(color: scheme.error),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_outlined,
                                size: 18,
                                color: scheme.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Guarda esta contraseña: si la olvidas, solo '
                                  'podrás recuperar el acceso restaurando una '
                                  'copia de seguridad.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: scheme.error),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: _saving ? null : _guardar,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check),
                            label: Text(
                              _saving ? 'Guardando…' : 'Guardar y continuar',
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: _saving ? null : _salir,
                            child: const Text('Cerrar sesión'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
