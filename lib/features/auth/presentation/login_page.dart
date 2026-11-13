import 'package:flutter/material.dart';

import '../../../core/app_info.dart';
import '../../../core/auth_repository.dart';
import '../../../core/session.dart';
import '../../../ui/common.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin});

  final ValueChanged<Usuario> onLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usuario = TextEditingController();
  final _password = TextEditingController();
  final _repository = AuthRepository();
  bool _loading = false;
  bool _verPassword = false;
  bool _credencialesPorDefecto = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkCredencialesPorDefecto();
  }

  Future<void> _checkCredencialesPorDefecto() async {
    try {
      final porDefecto = await _repository.usaCredencialesPorDefecto();
      if (!mounted) return;
      setState(() => _credencialesPorDefecto = porDefecto);
    } catch (_) {
      // Si falla la consulta, simplemente no se muestra la pista.
    }
  }

  @override
  void dispose() {
    _usuario.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final usuario = await _repository.login(_usuario.text, _password.text);
      if (!mounted) return;
      if (usuario == null) {
        setState(() {
          _error = 'Usuario o contraseña incorrectos.';
          _loading = false;
        });
        return;
      }
      widget.onLogin(usuario);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo iniciar sesión: $error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
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
                constraints: const BoxConstraints(maxWidth: 430),
                child: AppCard(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.restaurant_menu,
                              color: scheme.onPrimary, // Blanco cálido
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Text(
                              appNombre,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                appCanal,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: scheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Control de ventas, caja e inventario',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: _usuario,
                          textInputAction: TextInputAction.next,
                          decoration: appInput(
                            label: 'Usuario',
                            icon: Icons.person_outline,
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? 'Ingresa tu usuario'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          obscureText: !_verPassword,
                          onFieldSubmitted: (_) => _ingresar(),
                          decoration: appInput(
                            label: 'Contraseña',
                            icon: Icons.lock_outline,
                            suffix: IconButton(
                              onPressed: () =>
                                  setState(() => _verPassword = !_verPassword),
                              icon: Icon(
                                _verPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => (value == null || value.isEmpty)
                              ? 'Ingresa tu contraseña'
                              : null,
                        ),
                        if (_credencialesPorDefecto) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(
                                alpha: 0.45,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Primer acceso: admin / 1234',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: scheme.primary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(_error!, style: TextStyle(color: scheme.error)),
                        ],
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _loading ? null : _ingresar,
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: Text(_loading ? 'Ingresando…' : 'Ingresar'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
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
    );
  }
}
