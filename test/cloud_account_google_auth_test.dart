import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/cloud/account_service.dart';
import 'package:openstrap_edge/ui2/profile/account_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AccountProfile serialization & Google Auth', () {
    test('serializes and deserializes Google profile attributes', () {
      final now = DateTime.now();
      const profile = AccountProfile(
        email: 'user@gmail.com',
        displayName: 'Test User',
        photoUrl: 'https://lh3.googleusercontent.com/test',
        authProvider: 'google',
        token: 'mock_jwt_token',
        userId: 'goog_123456789',
        serverUrl: 'https://cloud.openstrap.org',
        autoSync: true,
      );

      final json = profile.toJson();
      expect(json['email'], 'user@gmail.com');
      expect(json['displayName'], 'Test User');
      expect(json['photoUrl'], 'https://lh3.googleusercontent.com/test');
      expect(json['authProvider'], 'google');
      expect(json['userId'], 'goog_123456789');

      final reconstructed = AccountProfile.fromJson(json);
      expect(reconstructed.email, profile.email);
      expect(reconstructed.displayName, 'Test User');
      expect(reconstructed.photoUrl, 'https://lh3.googleusercontent.com/test');
      expect(reconstructed.authProvider, 'google');
      expect(reconstructed.token, 'mock_jwt_token');
      expect(reconstructed.userId, 'goog_123456789');
    });

    test('backward compatibility: legacy profile defaults to email auth provider', () {
      final legacyJson = {
        'email': 'legacy@example.com',
        'token': 'tok_xyz',
        'userId': 'usr_999',
        'autoSync': true,
      };

      final profile = AccountProfile.fromJson(legacyJson);
      expect(profile.email, 'legacy@example.com');
      expect(profile.authProvider, 'email');
      expect(profile.displayName, isNull);
      expect(profile.photoUrl, isNull);
    });

    test('copyWith properly updates Google profile fields', () {
      const initial = AccountProfile(
        email: 'initial@gmail.com',
        authProvider: 'email',
      );

      final updated = initial.copyWith(
        displayName: 'Google Name',
        authProvider: 'google',
        photoUrl: 'https://avatar.url',
      );

      expect(updated.email, 'initial@gmail.com');
      expect(updated.displayName, 'Google Name');
      expect(updated.authProvider, 'google');
      expect(updated.photoUrl, 'https://avatar.url');
    });
  });

  group('AccountScreen UI', () {
    testWidgets('renders Sign in with Google option when logged out', (tester) async {
      await AccountService.instance.init();
      if (AccountService.instance.isLoggedIn) {
        await AccountService.instance.logOut();
      }

      await tester.pumpWidget(
        const MaterialApp(
          home: AccountScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('or with email'), findsOneWidget);
      expect(find.text('Sign In with Email'), findsOneWidget);
    });
  });
}
