import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profiles/state/profiles_provider.dart';
import '../data/venue_api_client.dart';

/// The [VenueApiClient] for the currently-selected server profile, or null when
/// no profile is configured (or it has no address). Every feature that talks to
/// the venue server reads this; it rebuilds automatically when the user selects
/// or edits a profile.
final venueApiClientProvider = Provider<VenueApiClient?>((ref) {
  final entry = ref.watch(currentApiEntryProvider);
  if (entry == null || entry.ip.trim().isEmpty) return null;
  return VenueApiClient(host: entry.ip, apiKey: entry.apiKey);
});
