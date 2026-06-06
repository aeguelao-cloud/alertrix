import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/auth_models.dart';
import '../widgets/ui_kit.dart';
import 'forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onLogin,
    required this.apiBaseUrl,
  });

  final void Function(String username, UserRole role) onLogin;
  final String? apiBaseUrl;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const Color _inputHint = Color(0xFF8BA0AA);

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _registerPasswordFocusNode = FocusNode();
  final FocusNode _registerConfirmPasswordFocusNode = FocusNode();

  bool _registerMode = false;
  bool _busy = false;
  bool _isLoading = false;
  bool _rememberMe = true;
  String? _errorText;
  int _sendCodeSecondsLeft = 0;
  bool _hasSentCode = false;
  Timer? _sendCodeTimer;
  bool _registerPasswordReadyForInput = false;
  bool _registerConfirmPasswordReadyForInput = false;
  bool _obscureLoginPassword = true;
  bool _obscureRegisterPassword = true;
  bool _obscureRegisterConfirmPassword = true;

  bool get _hasApi => (widget.apiBaseUrl ?? '').trim().isNotEmpty;
  bool get _canSendCode => !_busy && _sendCodeSecondsLeft == 0;

  @override
  void dispose() {
    _sendCodeTimer?.cancel();
    _nameController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    _registerPasswordFocusNode.dispose();
    _registerConfirmPasswordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiColors.pageBg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final desktop = constraints.maxWidth >= 850;
          return SafeArea(
            child: desktop ? _buildDesktopLayout(size) : _buildMobileLayout(),
          );
        },
      ),
    );
  }

  Widget _buildDesktopLayout(Size size) {
    final leftWidth = size.width * 0.36;

    return Row(
      children: [
        SizedBox(
          width: leftWidth,
          child: _buildBrandPanel(desktop: true),
        ),
        Expanded(
          child: Container(
            color: UiColors.pageBg,
            padding: const EdgeInsets.all(44),
            alignment: Alignment.center,
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: _buildAuthCard(compact: false),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _buildAuthCard(compact: true),
        ),
      ),
    );
  }

  Widget _buildBrandPanel({required bool desktop}) {
    final horizontal = desktop ? 36.0 : 24.0;

    return Container(
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF04142A),
            Color(0xFF062748),
            Color(0xFF031A35),
          ],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _PanelSceneryPainter()),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.06),
                    Colors.black.withValues(alpha: 0.24),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(horizontal, 56, horizontal, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              const Color(0xFFAAF0FF).withValues(alpha: 0.86),
                          width: 2,
                        ),
                        color: const Color(0xFF0F3B59).withValues(alpha: 0.6),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: Color(0xFF9CF2FF),
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Alertrix',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 54,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Disaster Monitoring &\nEarly Warning System',
                  style: TextStyle(
                    color: Color(0xFFDCEAF8),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    height: 1.32,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  width: 72,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF24D2E8),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 34),
                const _BrandFeature(
                  icon: Icons.wifi_tethering_rounded,
                  title: 'Real-time Monitoring',
                ),
                const SizedBox(height: 18),
                const _BrandFeature(
                  icon: Icons.notifications_active_outlined,
                  title: 'Smart Alerts',
                ),
                const SizedBox(height: 18),
                const _BrandFeature(
                  icon: Icons.cloud_outlined,
                  title: 'Cloud Integration',
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard({required bool compact}) {
    final title = _registerMode ? 'Create Account' : 'Welcome Back';
    final subtitle = _registerMode
        ? 'Create your Alertrix account with email verification.'
        : 'Sign in to your Alertrix account';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 24 : 46),
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: UiColors.border.withValues(alpha: 0.86)),
        boxShadow: [
          BoxShadow(
            color: UiColors.brandDark.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: compact ? 28 : 44,
              fontWeight: FontWeight.w800,
              height: 1.02,
              color: UiColors.textStrong,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: compact ? 14 : 16,
              color: UiColors.textBody,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),
          if (_registerMode) ..._buildRegisterForm() else ..._buildSignInForm(),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: const TextStyle(
                color: UiColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: UiColors.brand,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: (_busy || _isLoading)
                  ? null
                  : () => _runPrimaryAction(
                        _registerMode ? _register : _login,
                      ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(_registerMode ? 'Create Account' : 'Sign In'),
            ),
          ),
          if (_registerMode)
            const SizedBox(height: 14)
          else
            const SizedBox(height: 24),
          if (_registerMode)
            Align(
              alignment: Alignment.center,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Already have an account?',
                    style: TextStyle(
                      fontSize: 14,
                      color: UiColors.textMuted,
                    ),
                  ),
                  TextButton(
                    onPressed: (_busy || _isLoading)
                        ? null
                        : () => _switchAuthMode(false),
                    style: uiLinkButton(),
                    child: const Text('Sign in'),
                  ),
                ],
              ),
            )
          else ...[
            const Row(
              children: [
                Expanded(child: Divider(color: UiColors.border)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'or',
                    style: TextStyle(
                      color: UiColors.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: UiColors.border)),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: OutlinedButton.icon(
                onPressed:
                    (_busy || _isLoading) ? null : () => _switchAuthMode(true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: UiColors.brand,
                  side:
                      const BorderSide(color: UiColors.borderStrong, width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                icon: const Icon(Icons.person_add_alt_rounded, size: 22),
                label: const Text('Create Account'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Row(
            children: [
              Text(
                '(c) 2026 Alertrix',
                style: TextStyle(
                  fontSize: 12,
                  color: UiColors.textMuted,
                ),
              ),
              Spacer(),
              Text(
                'Privacy Policy',
                style: TextStyle(
                  fontSize: 12,
                  color: UiColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRegisterForm() {
    return [
      _buildFieldLabel('Username'),
      _buildInput(
        controller: _nameController,
        hintText: 'Username',
        textInputAction: TextInputAction.next,
        prefixIcon: Icons.person_outline_rounded,
        onChanged: _handleVerificationIdentityChanged,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
      ),
      const SizedBox(height: 12),
      _buildFieldLabel('Email'),
      _buildInput(
        controller: _emailController,
        hintText: 'you@example.com',
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        prefixIcon: Icons.mail_outline_rounded,
        onChanged: _handleVerificationIdentityChanged,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        height: 56,
        child: OutlinedButton(
          onPressed: _canSendCode && !_isLoading ? _sendCode : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: UiColors.brand,
            backgroundColor: UiColors.surfaceAlt,
            side: const BorderSide(color: UiColors.borderStrong, width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(UiRadius.button),
            ),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          child: Text(
            _sendCodeSecondsLeft > 0
                ? 'Resend ${_sendCodeSecondsLeft}s'
                : (_hasSentCode ? 'Resend code' : 'Send code'),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _buildFieldLabel('Verification code'),
      _buildInput(
        controller: _codeController,
        hintText: '6-digit code',
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        prefixIcon: Icons.pin_outlined,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
      ),
      const SizedBox(height: 16),
      _buildFieldLabel('Password'),
      _buildInput(
        controller: _passwordController,
        focusNode: _registerPasswordFocusNode,
        hintText: 'Password',
        obscureText: _obscureRegisterPassword,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.next,
        prefixIcon: Icons.lock_outline_rounded,
        autofillHints: const [AutofillHints.newPassword],
        enableSuggestions: false,
        autocorrect: false,
        enableIMEPersonalizedLearning: false,
        readOnly: !_registerPasswordReadyForInput,
        onTap: () => _enableRegisterPasswordInput(
          focusNode: _registerPasswordFocusNode,
          confirmPassword: false,
        ),
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        suffixIcon: _buildPasswordToggle(
          obscured: _obscureRegisterPassword,
          onPressed: () {
            setState(
                () => _obscureRegisterPassword = !_obscureRegisterPassword);
          },
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Minimum 8 characters',
        style: TextStyle(fontSize: 13, color: _inputHint),
      ),
      const SizedBox(height: 12),
      _buildFieldLabel('Confirm password'),
      _buildInput(
        controller: _confirmPasswordController,
        focusNode: _registerConfirmPasswordFocusNode,
        hintText: 'Confirm password',
        obscureText: _obscureRegisterConfirmPassword,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.done,
        prefixIcon: Icons.lock_person_outlined,
        autofillHints: const [AutofillHints.newPassword],
        enableSuggestions: false,
        autocorrect: false,
        enableIMEPersonalizedLearning: false,
        readOnly: !_registerConfirmPasswordReadyForInput,
        onTap: () => _enableRegisterPasswordInput(
          focusNode: _registerConfirmPasswordFocusNode,
          confirmPassword: true,
        ),
        onSubmitted: (_) => _submitRegisterWithKeyboard(),
        suffixIcon: _buildPasswordToggle(
          obscured: _obscureRegisterConfirmPassword,
          onPressed: () {
            setState(() {
              _obscureRegisterConfirmPassword =
                  !_obscureRegisterConfirmPassword;
            });
          },
        ),
      ),
    ];
  }

  List<Widget> _buildSignInForm() {
    return [
      _buildFieldLabel('Email'),
      _buildInput(
        controller: _loginController,
        hintText: 'you@example.com',
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        prefixIcon: Icons.mail_outline_rounded,
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
      ),
      const SizedBox(height: 16),
      _buildFieldLabel('Password'),
      _buildInput(
        controller: _passwordController,
        hintText: 'Enter your password',
        obscureText: _obscureLoginPassword,
        textInputAction: TextInputAction.done,
        prefixIcon: Icons.lock_outline_rounded,
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
        onSubmitted: (_) => _submitLoginWithKeyboard(),
        suffixIcon: _buildPasswordToggle(
          obscured: _obscureLoginPassword,
          onPressed: () {
            setState(() => _obscureLoginPassword = !_obscureLoginPassword);
          },
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _rememberMe = !_rememberMe),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _rememberMe,
                    activeColor: UiColors.brand,
                    onChanged: (value) {
                      setState(() => _rememberMe = value ?? false);
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Remember me',
                  style: TextStyle(
                    color: UiColors.textBody,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: (_busy || _isLoading) ? null : _forgotPassword,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 0),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Forgot Password?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: UiColors.brand,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: UiColors.textBody,
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    FocusNode? focusNode,
    required String hintText,
    bool obscureText = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    Iterable<String>? autofillHints,
    bool enableSuggestions = true,
    bool autocorrect = true,
    bool enableIMEPersonalizedLearning = true,
    bool readOnly = false,
    IconData? prefixIcon,
    Widget? suffixIcon,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    ValueChanged<String>? onChanged,
    GestureTapCallback? onTap,
  }) {
    return SizedBox(
      height: 56,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        autofillHints: autofillHints,
        enableSuggestions: enableSuggestions,
        autocorrect: autocorrect,
        enableIMEPersonalizedLearning: enableIMEPersonalizedLearning,
        readOnly: readOnly,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        onTap: onTap,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        decoration: _inputDecoration(
          hintText,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String hintText, {
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(fontSize: 16, color: _inputHint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      suffixIcon: suffixIcon,
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, size: 20, color: UiColors.textMuted),
      filled: true,
      fillColor: UiColors.surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UiRadius.input),
        borderSide: const BorderSide(color: UiColors.border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UiRadius.input),
        borderSide: const BorderSide(color: UiColors.border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UiRadius.input),
        borderSide: const BorderSide(color: UiColors.brand, width: 2),
      ),
    );
  }

  Widget _buildPasswordToggle({
    required bool obscured,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      splashRadius: 20,
      tooltip: obscured ? 'Show password' : 'Hide password',
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
        color: UiColors.textMuted,
      ),
    );
  }

  void _submitLoginWithKeyboard() {
    if (_busy || _isLoading || _registerMode) return;
    _runPrimaryAction(_login);
  }

  void _submitRegisterWithKeyboard() {
    if (_busy || _isLoading || !_registerMode) return;
    _runPrimaryAction(_register);
  }

  void _switchAuthMode(bool registerMode) {
    setState(() {
      _registerMode = registerMode;
      _errorText = null;
      _passwordController.clear();
      _confirmPasswordController.clear();
      _registerPasswordReadyForInput = false;
      _registerConfirmPasswordReadyForInput = false;
      _resetSendCodeState();
    });
  }

  void _enableRegisterPasswordInput({
    required FocusNode focusNode,
    required bool confirmPassword,
  }) {
    final alreadyReady = confirmPassword
        ? _registerConfirmPasswordReadyForInput
        : _registerPasswordReadyForInput;
    if (alreadyReady) return;

    setState(() {
      if (confirmPassword) {
        _registerConfirmPasswordReadyForInput = true;
      } else {
        _registerPasswordReadyForInput = true;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusNode.requestFocus();
    });
  }

  void _handleVerificationIdentityChanged(String _) {
    if (_errorText == null &&
        !_hasSentCode &&
        _sendCodeSecondsLeft == 0 &&
        _codeController.text.isEmpty) {
      return;
    }
    setState(() {
      _errorText = null;
      _resetSendCodeState();
    });
  }

  void _resetSendCodeState() {
    _sendCodeTimer?.cancel();
    _sendCodeTimer = null;
    _sendCodeSecondsLeft = 0;
    _hasSentCode = false;
    _codeController.clear();
  }

  Future<void> _sendCode() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty || email.isEmpty) {
      setState(() => _errorText = 'Username and email are required.');
      return;
    }
    if (!_hasApi) {
      setState(() => _errorText = 'API base URL missing.');
      return;
    }

    await _runBusy(() async {
      final resp = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/auth/send-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'email': email}),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(
            _extractError(resp.body, fallback: 'Failed to send code'));
      }
      if (!mounted) return;
      _startSendCodeCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code sent. Check your email.')),
      );
    });
  }

  void _startSendCodeCooldown() {
    _sendCodeTimer?.cancel();
    setState(() {
      _sendCodeSecondsLeft = 60;
      _hasSentCode = true;
    });
    _sendCodeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_sendCodeSecondsLeft <= 1) {
        timer.cancel();
        setState(() => _sendCodeSecondsLeft = 0);
      } else {
        setState(() => _sendCodeSecondsLeft -= 1);
      }
    });
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    if (name.isEmpty || password.isEmpty || email.isEmpty || code.isEmpty) {
      setState(() => _errorText = 'All fields are required.');
      return;
    }
    if (email.toLowerCase() == 'admin@alertrix.local') {
      setState(() =>
          _errorText = 'Admin account cannot be registered from this page.');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _errorText = 'Enter a valid 6-digit verification code.');
      return;
    }
    if (password.length < 8) {
      setState(() => _errorText = 'Password must be at least 8 characters.');
      return;
    }
    if (password != confirmPassword) {
      setState(
          () => _errorText = 'Password and confirm password do not match.');
      return;
    }
    if (!_hasApi) {
      setState(() => _errorText = 'API base URL missing.');
      return;
    }

    await _runBusy(() async {
      final resp = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'password': password,
          'email': email,
          'code': code,
        }),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(
            _extractError(resp.body, fallback: 'Registration failed'));
      }
      if (!mounted) return;
      setState(() {
        _registerMode = false;
        _errorText = null;
        _codeController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created. Please sign in.')),
      );
    });
  }

  Future<void> _login() async {
    final email = _loginController.text.trim();
    final password = _passwordController.text;
    final emailLower = email.toLowerCase();

    if (!_hasApi && emailLower == 'admin@alertrix.local') {
      if (password == 'Admin@123') {
        // Keep internal admin id aligned with backend admin guard.
        widget.onLogin(emailLower, UserRole.admin);
      } else {
        setState(() => _errorText = 'Invalid internal admin credentials.');
      }
      return;
    }

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorText = 'Email and password are required.');
      return;
    }

    if (!_hasApi) {
      final fallbackUsername =
          email.contains('@') ? email.split('@').first.trim() : email.trim();
      widget.onLogin(
        fallbackUsername.isEmpty ? 'demo_user' : fallbackUsername,
        UserRole.operator,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('API base URL missing. Signed in using local demo mode.'),
        ),
      );
      return;
    }

    await _runBusy(() async {
      final resp = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'login': email,
          'password': password,
        }),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(_extractError(resp.body, fallback: 'Login failed'));
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final user = json['user'] as Map<String, dynamic>? ?? const {};
      final roleText = (user['role']?.toString() ?? 'User').toLowerCase();
      final role = roleText == 'admin' ? UserRole.admin : UserRole.operator;
      final actualUsername = user['username']?.toString() ?? email;
      widget.onLogin(actualUsername, role);
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _errorText = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _extractError(String body, {required String fallback}) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['error']?.toString() ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _forgotPassword() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordPage(
          apiBaseUrl: widget.apiBaseUrl,
          initialEmail: _loginController.text.trim(),
        ),
      ),
    );
  }

  Future<void> _runPrimaryAction(Future<void> Function() action) async {
    if (_busy || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      await Future<void>.delayed(const Duration(seconds: 1));
      await action();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _BrandFeature extends StatelessWidget {
  const _BrandFeature({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF69E2F8).withValues(alpha: 0.65),
            ),
            color: const Color(0xFF0E3152).withValues(alpha: 0.48),
          ),
          child: Icon(icon, color: const Color(0xFF80EFFF), size: 30),
        ),
        const SizedBox(width: 16),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFE8F4FE),
            fontSize: 16,
            fontWeight: FontWeight.w500,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

class _PanelSceneryPainter extends CustomPainter {
  const _PanelSceneryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final skyline = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFF0B2D4A).withValues(alpha: 0.85),
          const Color(0xFF071F36).withValues(alpha: 0.97),
        ],
      ).createShader(
        Rect.fromLTWH(0, size.height * 0.56, size.width, size.height * 0.44),
      );

    final groundPath = Path()
      ..moveTo(0, size.height * 0.84)
      ..quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.76,
        size.width * 0.56,
        size.height * 0.83,
      )
      ..quadraticBezierTo(
        size.width * 0.8,
        size.height * 0.9,
        size.width,
        size.height * 0.83,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(groundPath, skyline);

    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF46E3FF).withValues(alpha: 0.35);
    final nodePaint = Paint()..color = const Color(0xFF78F0FF);
    final networkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xFF4FDEFF).withValues(alpha: 0.24);

    final baseY = size.height * 0.84;
    final nodes = <Offset>[
      Offset(size.width * 0.12, baseY + 10),
      Offset(size.width * 0.24, baseY - 22),
      Offset(size.width * 0.41, baseY + 6),
      Offset(size.width * 0.56, baseY - 18),
      Offset(size.width * 0.7, baseY + 4),
      Offset(size.width * 0.86, baseY - 12),
    ];

    for (var i = 0; i < nodes.length - 1; i++) {
      canvas.drawLine(nodes[i], nodes[i + 1], networkPaint);
    }

    for (final n in nodes) {
      canvas.drawCircle(n, 10, glowPaint);
      canvas.drawCircle(n, 3, nodePaint);
    }

    final towerX = size.width * 0.52;
    final towerTop = size.height * 0.74;
    final towerBottom = size.height * 0.91;
    final towerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF4EDFFF).withValues(alpha: 0.55);

    final tower = Path()
      ..moveTo(towerX, towerTop)
      ..lineTo(towerX - 24, towerBottom)
      ..lineTo(towerX + 24, towerBottom)
      ..close()
      ..moveTo(towerX - 18, towerBottom - 42)
      ..lineTo(towerX + 18, towerBottom - 42)
      ..moveTo(towerX - 13, towerBottom - 24)
      ..lineTo(towerX + 13, towerBottom - 24)
      ..moveTo(towerX, towerTop)
      ..lineTo(towerX, towerBottom);
    canvas.drawPath(tower, towerPaint);

    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF68ECFF).withValues(alpha: 0.35);
    canvas.drawCircle(Offset(towerX, towerTop - 2), 10, nodePaint);
    canvas.drawCircle(Offset(towerX, towerTop - 2), 22, pulsePaint);
    canvas.drawCircle(Offset(towerX, towerTop - 2), 34, pulsePaint);

    final lightningPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF2F8FF).withValues(alpha: 0.22);

    final bolt = Path()
      ..moveTo(size.width * 0.84, size.height * 0.18)
      ..lineTo(size.width * 0.8, size.height * 0.3)
      ..lineTo(size.width * 0.84, size.height * 0.3)
      ..lineTo(size.width * 0.79, size.height * 0.42);
    canvas.drawPath(bolt, lightningPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
