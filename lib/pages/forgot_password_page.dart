import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../widgets/ui_kit.dart';

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
  static const Color _inputHint = Color(0xFF8BA0AA);

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  Timer? _sendCodeTimer;
  int _sendCodeSecondsLeft = 0;
  bool _hasSentCode = false;
  bool _busy = false;
  bool _isLoading = false;
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
        SizedBox(width: leftWidth, child: _buildBrandPanel()),
        Expanded(
          child: Container(
            color: UiColors.pageBg,
            padding: const EdgeInsets.all(44),
            alignment: Alignment.center,
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: _buildResetCard(compact: false),
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
          child: _buildResetCard(compact: true),
        ),
      ),
    );
  }

  Widget _buildBrandPanel() {
    const horizontal = 36.0;

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
            padding: const EdgeInsets.fromLTRB(horizontal, 56, horizontal, 36),
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

  Widget _buildResetCard({required bool compact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 22 : 44),
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
            'Forgot Password',
            style: TextStyle(
              fontSize: compact ? 34 : 44,
              fontWeight: FontWeight.w800,
              height: 1.08,
              color: UiColors.textStrong,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Resend an email code and set a new password.',
            style: TextStyle(
              fontSize: compact ? 14 : 16,
              color: UiColors.textBody,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          _buildFieldLabel('Email'),
          _buildInput(
            controller: _emailController,
            hintText: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            prefixIcon: Icons.mail_outline_rounded,
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton(
              onPressed: _canSendCode && !_isLoading ? _sendResetCode : null,
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
                    : (_hasSentCode ? 'Resend Email Code' : 'Send Email Code'),
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
          const SizedBox(height: 12),
          _buildFieldLabel('New password'),
          _buildInput(
            controller: _newPasswordController,
            hintText: 'New password',
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            prefixIcon: Icons.lock_outline_rounded,
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
          const SizedBox(height: 12),
          _buildFieldLabel('Confirm new password'),
          _buildInput(
            controller: _confirmPasswordController,
            hintText: 'Confirm new password',
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            prefixIcon: Icons.lock_person_outlined,
            onSubmitted: (_) => _runPrimaryAction(_resetPassword),
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
                color: UiColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton(
              onPressed: (_busy || _isLoading)
                  ? null
                  : () => _runPrimaryAction(_resetPassword),
              style: uiPrimaryButton(),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Reset Password'),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: (_busy || _isLoading)
                  ? null
                  : () => Navigator.of(context).pop(),
              style: uiLinkButton(),
              child: const Text('Back to Sign In'),
            ),
          ),
        ],
      ),
    );
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
    required String hintText,
    bool obscureText = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    IconData? prefixIcon,
    Widget? suffixIcon,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return SizedBox(
      height: 56,
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
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          prefixIcon: prefixIcon == null
              ? null
              : Icon(prefixIcon, size: 20, color: UiColors.textMuted),
          suffixIcon: suffixIcon,
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
        color: UiColors.textMuted,
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

  String _extractError(String body, {required String fallback}) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['error']?.toString() ?? fallback;
    } catch (_) {
      return fallback;
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
