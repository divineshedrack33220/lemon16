import 'package:flutter/material.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/create_post_screen.dart';
import 'screens/chats_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/nearby_screen.dart';
import 'screens/view_profile_screen.dart';
import 'screens/group_join_screen.dart';
// import 'screens/settings_screen.dart'; // Remove if you don't have this yet

import 'services/notification_service.dart';
import 'widgets/network_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  runApp(const Lemon16App());
}

class Lemon16App extends StatelessWidget {
  const Lemon16App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zukaping',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return NetworkWrapper(child: child!);
      },
      theme: ThemeData(
        primaryColor: const Color(0xFF00AEEF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00AEEF),
          primary: const Color(0xFF00AEEF),
          secondary: const Color(0xFF00AEEF),
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00AEEF),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
            minimumSize: const Size(double.infinity, 56),
            elevation: 0,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF8E8E8E)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF00AEEF), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF453A)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF453A), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          filled: true,
          fillColor: Colors.white,
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF00AEEF),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF00AEEF),
          foregroundColor: Colors.black,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: const Color(0xFF00AEEF),
          contentTextStyle: const TextStyle(color: Colors.white),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/feed': (context) => const FeedScreen(),
        '/create-post': (context) => const CreatePostScreen(),
        '/chats': (context) => const ChatsScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/edit-profile': (context) => const EditProfileScreen(),
        '/favorites': (context) => const FavoritesScreen(),
        '/nearby': (context) => const NearbyScreen(),
        // '/settings': (context) => const SettingsScreen(), // Uncomment when created
      },
      onGenerateRoute: (settings) {
        // Handle routes with arguments
        
        // Chat screen - can accept chatId or userId
        if (settings.name == '/chat') {
          final args = settings.arguments as Map<String, dynamic>?;
          final chatId = args?['chatId'] as String?;
          final userId = args?['userId'] as String?;
          
          return MaterialPageRoute(
            builder: (context) => ChatScreen(
              chatId: chatId,
              userId: userId,
            ),
          );
        }
        
        // View profile screen - requires userId
        if (settings.name == '/view-profile') {
          final args = settings.arguments as Map<String, dynamic>?;
          final userId = args?['userId'] as String? ?? '';
          
          return MaterialPageRoute(
            builder: (context) => ViewProfileScreen(userId: userId),
          );
        }

        // Group Join Screen - requires inviteCode
        if (settings.name == '/join-group') {
          final args = settings.arguments as Map<String, dynamic>?;
          final inviteCode = args?['inviteCode'] as String? ?? '';
          
          return MaterialPageRoute(
            builder: (context) => GroupJoinScreen(inviteCode: inviteCode),
          );
        }

        // Signup screen - can accept inviteCode
        if (settings.name == '/signup') {
          final args = settings.arguments as Map<String, dynamic>?;
          final inviteCode = args?['inviteCode'] as String?;
          
          return MaterialPageRoute(
            builder: (context) => SignupScreen(inviteCode: inviteCode),
          );
        }

        // Login screen - can accept inviteCode
        if (settings.name == '/login') {
          final args = settings.arguments as Map<String, dynamic>?;
          final inviteCode = args?['inviteCode'] as String?;
          
          return MaterialPageRoute(
            builder: (context) => LoginScreen(inviteCode: inviteCode),
          );
        }
        
        return null;
      },
    );
  }
}