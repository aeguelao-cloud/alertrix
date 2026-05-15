import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({
    super.key,
    required this.apiBaseUrl,
    this.initialEmail,
  });

  final String? apiBaseUrl;
  final String? initialEmail;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  static const Color _brandColor = Color(0xFF0A7E8C);
  static const Color _cardBackground = Colors.white;
  static const Color _titleColor = Color(0xFF101A1F);
  static const Color _bodyColor = Color(0xFF5C7580);
  static const Color _inputBorder = Color(0xFFDEE8ED);
  static const Color _inputHint = Color(0xFFA0B1BB);

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  Timer? _sendCodeTimer;
  int _sendCodeSecondsLeft = 0;
  bool _hasSentCode = false;
  bool _busy = false;
  String? _errorText;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  bool get _hasApi => (widget.apiBaseUrl ?? '').trim().isNotEmpty;
  bool get _canSendCode => !_busy && _sendCodeSecondsLeft == 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEmail?.trim() ?? '';
    if (initial.isNotEmpty) {
      _emailController.text = initial;
    }
  }

  @override
  void dispose() {
    _sendCodeTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Forgot Password',
                      style: TextStyle(
                        fontSize: compact ? 34 : 52,
                        fontWeight: FontWeight.w700,
                        height: compact ? 1.12 : 1.08,
                        color: _titleColor,
                      ),
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    Text(
                      'Resend an email code and set a new password.',
                      style: TextStyle(
                        fontSize: compact ? 14 : 16,
                        color: _bodyColor,
                        height: 1.45,
                      ),
                    ),
                    SizedBox(height: compact ? 16 : 24),
                    _buildInput(
                      controller: _emailController,
                      hintText: 'Email',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _canSendCode ? _sendResetCode : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _brandColor,
                          backgroundColor: const Color(0xFFF8FCFD),
                          side: const BorderSide(
                            color: Color(0xFFAED9DE),
                            width: 1,
                          ),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: Text(
                          _sendCodeSecondsLeft > 0
                              ? 'Resend ${_sendCodeSecondsLeft}s'
                              : (_hasSentCode
                                  ? 'Resend Email Code'
                                  : 'Send Email Code'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildInput(
                      controller: _codeController,
                      hintText: 'Verification code',
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
                      controller: _newPasswordController,
                      hintText: 'New password',
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      suffixIcon: _buildPasswordToggle(
                        obscured: _obscurePassword,
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Minimum 8 characters',
                      style: TextStyle(fontSize: 13, color: _inputHint),
                    ),
                    const SizedBox(height: 14),
                    _buildInput(
                      controller: _confirmPasswordController,
                      hintText: 'Confirm new password',
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _resetPassword(),
                      suffixIcon: _buildPasswordToggle(
                        obscured: _obscureConfirm,
                        onPressed: () {
                          setState(() => _obscureConfirm = !_obscureConfirm);
                        },
                      ),
                    ),
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
                    SizedBox(height: compact ? 16 : 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: _busy ? null : _resetPassword,
                        style: FilledButton.styleFrom(
                          backgroundColor: _brandColor,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Reset Password'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
                        child: const Text('Back to Sign In'),
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

  Widget _buildInput({
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    Widget? suffixIcon,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return SizedBox(
      height: 52,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(fontSize: 16, color: _inputHint),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        ),
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
        color: const Color(0xFF89A0AA),
      ),
    );
  }

  Future<void> _sendResetCode() async {
    if (!_hasApi) {
      setState(() {
        _errorText =
            'Forgot password requires backend API. Please set API_BASE_URL.';
      });
      return;
    }
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      setState(() => _errorText = 'Email is required.');
      return;
    }

    await _runBusy(() async {
      final resp = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/auth/send-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': 'Password Reset',
          'email': email,
          'purpose': 'reset',
        }),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(
            _extractError(resp.body, fallback: 'Failed to send reset code'));
      }
      if (!mounted) return;
      _startSendCodeCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification code sent to your email.')),
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

  Future<void> _resetPassword() async {
    if (!_hasApi) {
      setState(() {
        _errorText =
            'Forgot password requires backend API. Please set API_BASE_URL.';
      });
      return;
    }
    final email = _emailController.text.trim().toLowerCase();
    final code = _codeController.text.trim();
    final password = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (email.isEmpty || code.isEmpty || password.isEmpty || confirm.isEmpty) {
      setState(() => _errorText = 'All fields are required.');
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
    if (password != confirm) {
      setState(
          () => _errorText = 'Password and confirm password do not match.');
      return;
    }

    await _runBusy(() async {
      final resp = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'code': code,
          'password': password,
        }),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(
            _extractError(resp.body, fallback: 'Failed to reset password'));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Password reset successful. Please sign in.')),
      );
      Navigator.of(context).pop();
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
}
