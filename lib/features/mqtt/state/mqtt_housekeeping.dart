/// How long an entry may sit in "Neposlane narudžbe" before the app clears it
/// on its own — both the blue items that were never sent and the red orders
/// that need the waiter.
///
/// 24 hours, so every shift starts on a clean list. Nothing older than that is
/// worth keeping: the kasa refuses any order more than ten minutes old, so a
/// leftover can't be delivered any more, and an unconfirmed one from yesterday
/// was either printed long ago or never will be. Left on the list it is only
/// noise — and worse, a red order from yesterday invites a resend that would
/// put yesterday's items on today's bill.
///
/// Deliberately a fixed rule with no setting: a waiter should never have to
/// decide how long a dead order is kept.
const mqttKeepUnsentFor = Duration(hours: 24);

/// How often the app looks for entries to clear. Nothing depends on the sweep
/// being prompt — an entry a few minutes past its day does no harm — so this
/// stays lazy enough to cost nothing.
const mqttHousekeepingInterval = Duration(minutes: 10);

/// Whether something last touched at [at] has outlived [mqttKeepUnsentFor].
///
/// A clock that jumped backwards gives a negative difference and so keeps the
/// entry: the phone's own clock is not worth deleting a waiter's order over.
bool mqttIsExpired(DateTime at, {DateTime? now}) =>
    (now ?? DateTime.now()).difference(at) >= mqttKeepUnsentFor;
