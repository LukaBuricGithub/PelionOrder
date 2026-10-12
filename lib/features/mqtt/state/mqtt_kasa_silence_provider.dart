import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many orders in a row left this phone and got no answer at all.
///
/// Not the same thing as a refusal: "nije u prodaji", "greška pisača" or
/// "zastarjela" are the kasa talking, and they reset this to zero. Only
/// silence counts — the order was published, the broker took it, and nothing
/// came back within the ten seconds (§11.6).
///
/// It exists because silence is the one outcome the waiter can't read from a
/// single order: one unconfirmed order usually means the phone was pocketed a
/// second after sending (see `MqttService.holdForOrderReplies`), but several in
/// a row mean the kasa itself has stopped answering this phone — and then
/// every further order goes out blind. A venue sent seven that way in one
/// evening; all were printed, none was ever confirmed, and nobody noticed
/// until the end of the shift.
///
/// Deliberately NOT saved: after a restart the app knows nothing about the
/// kasa, and the first send re-establishes the truth. A warning carried over
/// from yesterday would be noise.
class MqttKasaSilenceNotifier extends StateNotifier<int> {
  MqttKasaSilenceNotifier() : super(0);

  /// From this many unanswered orders on, the waiter is warned before sending.
  ///
  /// Two, not one: a single lost confirmation is the normal consequence of
  /// putting the phone away and must not raise an alarm.
  static const threshold = 2;

  /// The kasa answered something — whatever it said, it is listening.
  void answered() {
    if (state != 0) state = 0;
  }

  /// An order went out and the kasa said nothing.
  void unanswered() => state = state + 1;
}

final mqttKasaSilenceProvider =
    StateNotifierProvider<MqttKasaSilenceNotifier, int>(
      (ref) => MqttKasaSilenceNotifier(),
    );

/// Whether the kasa has stopped confirming this phone's orders — enough to
/// tell the waiter about before they send the next one.
final mqttKasaSilentProvider = Provider<bool>(
  (ref) =>
      ref.watch(mqttKasaSilenceProvider) >= MqttKasaSilenceNotifier.threshold,
);

/// "Zadnje dvije narudžbe nisu potvrđene" for [n], counting in words the way
/// the number is actually spoken: 2–4 take the nominative plural, 5 and more
/// the genitive ("Zadnjih 5 narudžbi nije potvrđeno").
String mqttKasaSilenceText(int n) {
  const words = {2: 'dvije', 3: 'tri', 4: 'četiri'};
  final word = words[n];
  if (word != null) return 'Zadnje $word narudžbe nisu potvrđene';
  return 'Zadnjih $n narudžbi nije potvrđeno';
}
