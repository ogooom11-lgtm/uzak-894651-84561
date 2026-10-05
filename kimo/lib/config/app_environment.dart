class AppEnvironment {
  /// Keep false while you design and test the app without Firebase.
  /// After running `flutterfire configure`, set this to true.
  static const bool useFirebase = true;

  /// Temporary local user id used when Firebase Auth is not connected yet.
  /// Replace it later with FirebaseAuth.instance.currentUser!.uid.
  static const String demoUserId = 'local_demo_user';

  static const Duration connectionTimeout = Duration(seconds: 10);
}
