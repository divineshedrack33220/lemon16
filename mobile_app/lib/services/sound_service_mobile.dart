import 'package:flutter/services.dart';

class SoundServiceImpl {
  static void playSent() {
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  }

  static void playReceived() {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
  }

  static void playFavorite() {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
  }
}
