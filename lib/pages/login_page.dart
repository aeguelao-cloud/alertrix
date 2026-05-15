import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/auth_models.dart';
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
  static const Color _brandColor = Color(0xFF0A7E8C);
  static const Color _cardBackground = Colors.white;
  static const Color _titleColor = Color(0xFF101A1F);
  static const Color _bodyColor = Color(0xFF5C7580);
  static const Color _mutedText = Color(0xFF899BA4);
  static const Color _inputBorder = Color(0xFFDEE8ED);
  static const Color _inputHint = Color(0xFFA0B1BB);

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  bool _registerMode = true;
  bool _busy = false;
  String? _errorText;
  int _sendCodeSecondsLeft = 0;
  bool _hasSentCode = false;
  Timer? _sendCodeTimer;
  bool _obscureLoginPassword = true;
  bool _obscureRegisterPassword = true;
  bool _obscureRegisterConfirmPassword = true;

  bool get _hasApi => (widget.apiBaseUrl ?? "").trim().isNotEmpty;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 460;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(compact ? 20 : 32),
                decoration: BoxDecoration(
                  color: _cardBackground,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12263B45),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _registerMode ? "Create account" : "Sign in",
                      style: TextStyle(
                        fontSize: compact ? 34 : 56,
                        fontWeight: FontWeight.w700,
                        height: compact ? 1.12 : 1.08,
                        color: _titleColor,
                      ),
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    Text(
                      _registerMode
                          ? "Create your account with email verification.\nAdmin accounts are issued internally."
                          : "Sign in to access Alertrix.\nAdmin accounts are issued internally.",
                      style: TextStyle(
                        fontSize: compact ? 14 : 16,
                        color: _bodyColor,
                        height: 1.45,
                      ),
                    ),
                    SizedBox(height: compact ? 14 : 20),
                    _buildAuthSwitch(),
                    SizedBox(height: compact ? 16 : 24),
                    if (_registerMode)
                      ..._buildRegisterForm()
                    else
                      ..._buildSignInForm(),
                    if (_errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _errorText!,
                        style: const TextStyle(
                          color: Color(0xFFC93C3C),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (_busy) ...[
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(),
                    ],
                    SizedBox(
                        height: _registerMode
                            ? (compact ? 16 : 24)
                            : (compact ? 14 : 20)),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _brandColor,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed:
                            _busy ? null : (_registerMode ? _register : _login),
                        child:
                            Text(_registerMode ? "Create account" : "Sign in"),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.center,
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _registerMode
                                ? "Already have an account?"
                                : "Don't have an account?",
                            style: const TextStyle(
                              fontSize: 14,
                              color: _mutedText,
                            ),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    _switchAuthMode(!_registerMode);
                                  },
                            style: TextButton.styleFrom(
                              foregroundColor: _brandColor,
                              minimumSize: const Size(0, 0),
                              padding: const EdgeInsets.only(left: 6, right: 2),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: Text(
                                _registerMode ? "Sign in" : "Create account"),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildRegisterForm() {
    return [
      _buildInput(
        controller: _nameController,
        hintText: "Username",
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
      ),
      const SizedBox(height: 14),
      _buildInput(
        controller: _emailController,
        hintText: "Email",
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton(
          onPressed: _canSendCode ? _sendCode : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: _brandColor,
            backgroundColor: const Color(0xFFF8FCFD),
            side: const BorderSide(color: Color(0xFFAED9DE), width: 1),
            shape: const StadiumBorder(),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          child: Text(
            _sendCodeSecondsLeft > 0
                ? "Resend ${_sendCodeSecondsLeft}s"
                : (_hasSentCode ? "Resend code" : "Send code"),
          ),
        ),
      ),
      const SizedBox(height: 14),
      _buildInput(
        controller: _codeController,
        hintText: "Verification code",
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
      ),
      const SizedBox(height: 14),
      _buildInput(
        controller: _passwordController,
        hintText: "Password",
        obscureText: _obscureRegisterPassword,
        autofillHints: const <String>[],
        textInputAction: TextInputAction.next,
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
        "Minimum 8 characters",
        style: TextStyle(fontSize: 13, color: _inputHint),
      ),
      const SizedBox(height: 16),
      _buildInput(
        controller: _confirmPasswordController,
        hintText: "Confirm password",
        obscureText: _obscureRegisterConfirmPassword,
        autofillHints: const <String>[],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) =>
            _registerMode ? _submitRegisterWithKeyboard() : null,
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
      _buildInput(
        controller: _loginController,
        hintText: "Email",
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
      ),
      const SizedBox(height: 14),
      _buildInput(
        controller: _passwordController,
        hintText: "Password",
        obscureText: _obscureLoginPassword,
        textInputAction: TextInputAction.done,
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
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _busy ? null : _forgotPassword,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 0),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            "Forgot password?",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF137F8B),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    Iterable<String>? autofillHints,
    Widget? suffixIcon,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      height: 52,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        autofillHints: autofillHints,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        decoration: _inputDecoration(hintText, suffixIcon: suffixIcon),
      ),
    );
  }

  InputDecoration _inputDecoration(String hintText, {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(fontSize: 16, color: _inputHint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _inputBorder, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _inputBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _brandColor, width: 1.6),
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
      tooltip: obscured ? "Show password" : "Hide password",
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
        color: const Color(0xFF89A0AA),
      ),
    );
  }

  void _submitLoginWithKeyboard() {
    if (_busy || _registerMode) return;
    _login();
  }

  void _submitRegisterWithKeyboard() {
    if (_busy || !_registerMode) return;
    _register();
  }

  void _switchAuthMode(bool registerMode) {
    setState(() {
      _registerMode = registerMode;
      _errorText = null;
      _passwordController.clear();
      _confirmPasswordController.clear();
      if (!registerMode) {
        _codeController.clear();
      }
    });
  }

  Widget _buildAuthSwitch() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment<bool>(value: true, label: Text("Create account")),
          ButtonSegment<bool>(value: false, label: Text("Sign in")),
        ],
        selected: {_registerMode},
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(40)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const BorderSide(color: Color(0xFFAED9DE), width: 1);
            }
            return const BorderSide(color: Color(0xFFD4E3E8), width: 1);
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFFE8F7F8);
            }
            return Colors.white;
          }),
          foregroundColor: const WidgetStatePropertyAll(Color(0xFF35545F)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
        ),
        onSelectionChanged: (v) {
          _switchAuthMode(v.first);
        },
      ),
    );
  }

  Future<void> _sendCode() async {
    if (!_hasApi) {
      setState(() => _errorText = "API base URL missing.");
      return;
    }
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty || email.isEmpty) {
      setState(() => _errorText = "Username and email are required.");
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
            _extractError(resp.body, fallback: "Failed to send code"));
      }
      if (!mounted) return;
      _startSendCodeCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Code sent. Check your email.")),
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
    if (!_hasApi) {
      setState(() => _errorText = "API base URL missing.");
      return;
    }
    final name = _nameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    if (name.isEmpty || password.isEmpty || email.isEmpty || code.isEmpty) {
      setState(() => _errorText = "All fields are required.");
      return;
    }
    if (email.toLowerCase() == "admin@alertrix.local") {
      setState(() =>
          _errorText = "Admin account cannot be registered from this page.");
      return;
    }
    if (password.length < 8) {
      setState(() => _errorText = "Password must be at least 8 characters.");
      return;
    }
    if (password != confirmPassword) {
      setState(
          () => _errorText = "Password and confirm password do not match.");
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
            _extractError(resp.body, fallback: "Registration failed"));
      }
      if (!mounted) return;
      setState(() {
        _registerMode = false;
        _errorText = null;
        _codeController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Account created. Please sign in.")),
      );
    });
  }

  Future<void> _login() async {
    final email = _loginController.text.trim();
    final password = _passwordController.text;
    final emailLower = email.toLowerCase();

    if (emailLower == "admin@alertrix.local") {
      if (password == "Admin@123") {
        // Keep internal admin id aligned with backend admin guard.
        widget.onLogin(emailLower, UserRole.admin);
      } else {
        setState(() => _errorText = "Invalid internal admin credentials.");
      }
      return;
    }

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorText = "Email and password are required.");
      return;
    }

    if (!_hasApi) {
      final fallbackUsername =
          email.contains("@") ? email.split("@").first.trim() : email.trim();
      widget.onLogin(
        fallbackUsername.isEmpty ? "demo_user" : fallbackUsername,
        UserRole.operator,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("API base URL missing. Signed in using local demo mode."),
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
        throw Exception(_extractError(resp.body, fallback: "Login failed"));
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final user = json['user'] as Map<String, dynamic>? ?? const {};
      final roleText = (user['role']?.toString() ?? "User").toLowerCase();
      final role = roleText == "admin" ? UserRole.admin : UserRole.operator;
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
}
