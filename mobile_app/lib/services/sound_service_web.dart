import 'package:flutter/services.dart';
import 'dart:js' as js;

class SoundServiceImpl {
  static void playSent() {
    HapticFeedback.lightImpact();
    _synthesizeWebSound('sent');
  }

  static void playReceived() {
    HapticFeedback.mediumImpact();
    _synthesizeWebSound('received');
  }

  static void playFavorite() {
    HapticFeedback.mediumImpact();
    _synthesizeWebSound('favorite');
  }

  static void _synthesizeWebSound(String type) {
    try {
      js.context.callMethod('eval', ["""
        (function() {
          try {
            var AudioCtx = window.AudioContext || window.webkitAudioContext;
            if (!AudioCtx) return;
            var context = new AudioCtx();
            var osc = context.createOscillator();
            var gain = context.createGain();
            
            osc.connect(gain);
            gain.connect(context.destination);
            
            var now = context.currentTime;
            
            if ('$type' === 'sent') {
              osc.type = 'sine';
              osc.frequency.setValueAtTime(420, now);
              osc.frequency.exponentialRampToValueAtTime(840, now + 0.08);
              
              gain.gain.setValueAtTime(0.12, now);
              gain.gain.exponentialRampToValueAtTime(0.01, now + 0.08);
              
              osc.start(now);
              osc.stop(now + 0.08);
            } else if ('$type' === 'received') {
              osc.type = 'sine';
              osc.frequency.setValueAtTime(580, now);
              osc.frequency.setValueAtTime(780, now + 0.08);
              
              gain.gain.setValueAtTime(0.10, now);
              gain.gain.exponentialRampToValueAtTime(0.01, now + 0.16);
              
              osc.start(now);
              osc.stop(now + 0.16);
            } else if ('$type' === 'favorite') {
              osc.type = 'triangle';
              osc.frequency.setValueAtTime(523.25, now);
              osc.frequency.setValueAtTime(659.25, now + 0.05);
              osc.frequency.setValueAtTime(783.99, now + 0.10);
              osc.frequency.setValueAtTime(1046.50, now + 0.15);
              
              gain.gain.setValueAtTime(0.12, now);
              gain.gain.exponentialRampToValueAtTime(0.01, now + 0.25);
              
              osc.start(now);
              osc.stop(now + 0.25);
            }
          } catch(e) {
            console.log('Web audio synth failed:', e);
          }
        })();
      """]);
    } catch (e) {
      print('Web audio synthesis call failed: $e');
    }
  }
}
