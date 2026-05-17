import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../services/websocket_service.dart';

class NetworkWrapper extends StatefulWidget {
  final Widget child;

  const NetworkWrapper({super.key, required this.child});

  @override
  State<NetworkWrapper> createState() => _NetworkWrapperState();
}

class _NetworkWrapperState extends State<NetworkWrapper> {
  bool _hasInternet = true;
  bool _showSuccessBanner = false;
  late StreamSubscription<List<ConnectivityResult>> _subscription;

  @override
  void initState() {
    super.initState();
    _checkInitialConnection();
    _subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      _updateConnectionState(results);
    });
  }

  Future<void> _checkInitialConnection() async {
    final results = await Connectivity().checkConnectivity();
    _updateConnectionState(results);
  }

  void _updateConnectionState(List<ConnectivityResult> results) {
    final hasInternet = !results.every((result) => result == ConnectivityResult.none);
    if (_hasInternet != hasInternet) {
      setState(() {
        _hasInternet = hasInternet;
        if (hasInternet) {
          _showSuccessBanner = true;
          WebSocketService.connect();
        } else {
          _showSuccessBanner = false;
        }
      });

      if (hasInternet) {
        Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _showSuccessBanner = false;
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!_hasInternet)
          Material(
            color: const Color(0xFFFF453A), // iOS Premium System Red
            child: SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 8),
                    Text(
                      'Offline Mode — Browsing Cached Data',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (_showSuccessBanner)
          Material(
            color: const Color(0xFF34C759), // iOS Premium System Green
            child: SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 8),
                    Text(
                      'Back Online — Syncing Zukaping...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: widget.child,
        ),
      ],
    );
  }
}
