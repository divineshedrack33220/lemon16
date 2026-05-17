import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  final String? inviteCode;
  const LoginScreen({super.key, this.inviteCode});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isButtonEnabled = false;
  
  final String _baseUrl = ApiService.baseUrl.replaceAll('/api', '');
  
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '12239007321-kcvn3r3asgef4ic341tnvbn2bpt8i9qg.apps.googleusercontent.com',
  );

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _validateForm() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    
    setState(() {
      _isButtonEnabled = email.isNotEmpty && password.isNotEmpty && _isValidEmail(email);
    });
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return emailRegex.hasMatch(email);
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser != null) {
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final idToken = googleAuth.idToken;
        
        if (idToken != null) {
          final result = await ApiService.googleAuth(idToken);
          
          if (result['error'] == true) {
            throw Exception(result['message'] ?? 'Authentication failed');
          }
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', result['token']);
          await prefs.setString('userId', result['userId']);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Google login successful!')),
            );
            
            if (result['isNewUser'] == true || result['hasCompletedOnboarding'] == false) {
              Navigator.pushReplacementNamed(context, '/onboarding');
            } else {
              Navigator.pushReplacementNamed(context, '/feed');
            }
          }
        } else {
          throw Exception("Failed to retrieve Google token");
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _login() async {
    if (!_isValidEmail(_emailController.text.trim())) {
      setState(() {
        _errorMessage = 'Please enter a valid email address';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('userId', data['userId']);
        
        if (widget.inviteCode != null && widget.inviteCode!.isNotEmpty) {
          try {
            await ApiService.joinGroupByInviteCode(widget.inviteCode!);
          } catch (e) {
            print('⚠️ Auto-joining group on login failed: $e');
          }
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Login successful!')),
          );
          Navigator.pushReplacementNamed(context, '/feed');
        }
      } else {
        String errorMsg = 'Invalid email or password';
        try {
          final errorData = jsonDecode(response.body);
          errorMsg = errorData['error'] ?? errorData['message'] ?? errorMsg;
        } catch (e) {
          errorMsg = 'Invalid email or password';
        }
        setState(() {
          _errorMessage = errorMsg;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Cannot connect to server. Please check your connection.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Logo
                        Container(
                          width: 100, height: 100,
                          decoration: const BoxDecoration(color: Color(0xFF00AEEF), shape: BoxShape.circle),
                          child: Center(
                            child: Image.asset('assets/logo.png', width: 60, height: 60),
                          ),
                        ),
                        
                        const SizedBox(height: 80),
                        
                        // Email input
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: 'Email address',
                            filled: true,
                            fillColor: const Color(0xFFF5F5F5),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Password input
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'Password',
                            filled: true,
                            fillColor: const Color(0xFFF5F5F5),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        
                        if (_errorMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_errorMessage, style: const TextStyle(color: Color(0xFFFF453A)), textAlign: TextAlign.center),
                          ),
                        
                        const SizedBox(height: 24),
                        
                        // Login button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: (_isButtonEnabled && !_isLoading) ? _login : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00AEEF),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                            ),
                            child: _isLoading
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Continue', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: Divider(color: Colors.grey[300])),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text('or', style: TextStyle(color: Colors.grey[600])),
                            ),
                            Expanded(child: Divider(color: Colors.grey[300])),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Google button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: _isLoading ? null : _handleGoogleSignIn,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFE0E0E0)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.network(
                                  'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3c/Google_Favicon_2025.svg/250px-Google_Favicon_2025.svg.png',
                                  width: 20,
                                  height: 20,
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Continue with Google',
                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Sign up link
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("Don't have an account? "),
                            GestureDetector(
                              onTap: () => Navigator.pushNamed(context, '/signup'),
                              child: const Text('Sign up', style: TextStyle(color: Color(0xFF00AEEF), fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
