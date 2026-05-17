import 'sound_service_stub.dart'
    if (dart.library.html) 'sound_service_web.dart'
    if (dart.library.io) 'sound_service_mobile.dart';

class SoundService {
  static void playSent() => SoundServiceImpl.playSent();
  static void playReceived() => SoundServiceImpl.playReceived();
  static void playFavorite() => SoundServiceImpl.playFavorite();
}
