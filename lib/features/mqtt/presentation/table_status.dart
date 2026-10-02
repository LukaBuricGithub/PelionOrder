import '../models/mqtt_tables.dart';

/// How a table is presented / behaves.
enum TableTileStatus {
  free, // openable → new order
  order, // your unsent local items (on any table) → openable, editable
  occupiedMine, // yours (or your order is arriving) → order screen, read-only
  occupiedOther, // occupied by a colleague → openable only with pravo 008
}

/// "Jesu li poslane sve narudžbe sa stola" — drawn as a corner badge, kept
/// separate from [TableTileStatus] so the answer never competes with the
/// tile's colour for the same pixels.
enum TableSendMark {
  /// No badge: nothing ordered here, or only an unsent draft (which the blue
  /// tile already shows on a free table) — neither on its way nor arrived.
  none,

  /// On its way: sent and waiting for the kasa's confirmation, or accepted by
  /// the kasa but not yet on the table — "šalje se". Amber ↑.
  pending,

  /// Everything sent from this device has reached the table. Green ✓.
  sent,

  /// An order in "Neposlane narudžbe" that didn't get through (not sent,
  /// refused, too old). Red !, and it wins over every other mark: it is the
  /// one a waiter must act on or at least know about.
  unsent,
}

/// Everything known about the tables right now, and the rules that turn it
/// into what a table looks like.
///
/// Shared by the two ways a venue's tables are drawn — the generic grid and
/// the venue's own floor plan (`podaci/tlocrt`) — so a table cannot mean one
/// thing on one screen and something else on the other.
class MqttTableFacts {
  const MqttTableFacts({
    required this.occupied,
    required this.withOrders,
    required this.pendingTransfer,
    required this.landed,
    required this.unsentBy,
    required this.sendingBy,
    required this.lockedBy,
    required this.userNames,
    required this.myCuser,
    required this.myName,
  });

  /// Occupied tables as DRAWN (live `stolovi_stanje` plus the ones held for a
  /// moment after they drop out of it).
  final Map<int, MqttTableState> occupied;

  /// Tables holding items typed on this phone and not sent yet.
  final Set<int> withOrders;

  /// Tables whose accepted order the kasa has not yet moved onto the table.
  final Set<int> pendingTransfer;

  /// Tables whose order has just landed but that `stolovi_stanje` doesn't list
  /// yet — drawn as ours with ✓, exactly as they will look once it does.
  final Set<int> landed;

  /// Tables with an order in "Neposlane narudžbe" that didn't get through,
  /// with the waiter who placed it (only orders this waiter may see).
  final Map<int, String> unsentBy;

  /// Tables with an order the broker holds, waiting for the kasa's
  /// confirmation, with the waiter who placed it.
  final Map<int, String> sendingBy;

  /// Tables the kasa has locked for someone ELSE, and who holds them
  /// (`CORD3`, or a kasa's tag). Our own lock is not in here.
  final Map<int, String> lockedBy;

  /// Waiter name by user code.
  final Map<String, String> userNames;
  final String? myCuser;

  /// Our own naziv — shown on a table whose order is still arriving.
  final String? myName;

  TableTileStatus statusFor(int broj) {
    // Locked by the kasa or another orderman: shown as taken and not
    // openable, even when it holds nothing — a cashier standing in an empty
    // table is exactly the case that isn't in `zauzeti` at all.
    if (lockedBy.containsKey(broj)) return TableTileStatus.occupiedOther;
    // Items added on this phone and not sent yet: blue, whatever else the
    // table is — also an occupied one, ours or (with pravo 008) a colleague's.
    // Once they are sent or removed, the table shows its usual colour again.
    if (withOrders.contains(broj)) return TableTileStatus.order;
    final occ = occupied[broj];
    if (occ != null) {
      return occ.cuser == myCuser
          ? TableTileStatus.occupiedMine
          : TableTileStatus.occupiedOther;
    }
    // Sent from this phone and accepted, but the kasa hasn't put it on the
    // table yet, so it isn't in stolovi_stanje. Show it as ours straight away
    // — the amber ↑ says it is still arriving — so that when it lands only the
    // badge changes, instead of a grey "free" table suddenly turning teal.
    if (pendingTransfer.contains(broj) || landed.contains(broj)) {
      return TableTileStatus.occupiedMine;
    }
    // An unconfirmed order: the table belongs to whoever placed it, even
    // though the kasa doesn't list it (yet).
    final unsentCuser = unsentBy[broj] ?? sendingBy[broj];
    if (unsentCuser != null) {
      return unsentCuser == myCuser
          ? TableTileStatus.occupiedMine
          : TableTileStatus.occupiedOther;
    }
    return TableTileStatus.free;
  }

  /// The corner badge — independent of [statusFor], so it answers a different
  /// question from the tile's colour: where is the order on its journey?
  ///
  /// Amber ↑ only while the kasa has an order but hasn't put it on the table;
  /// green ✓ once everything has landed. An unsent draft gets NO badge:
  /// nothing is on its way, so ↑ would suggest something was sent — and it
  /// must also stop an occupied table falling through to ✓, which would claim
  /// an unsent addition had arrived.
  TableSendMark markFor(int broj) {
    if (unsentBy.containsKey(broj)) return TableSendMark.unsent;
    if (sendingBy.containsKey(broj) || pendingTransfer.contains(broj)) {
      return TableSendMark.pending;
    }
    if (withOrders.contains(broj)) return TableSendMark.none;
    // Everything on the table has landed — but only mark a table that actually
    // has an order; an empty table has nothing to report.
    return occupied.containsKey(broj) || landed.contains(broj)
        ? TableSendMark.sent
        : TableSendMark.none;
  }

  /// Whose table it is, as shown on the tile. A locked table says only
  /// "Zauzeto" — who holds it is in the message shown when it is tapped,
  /// where there is room for it.
  String? occupantFor(int broj) {
    if (lockedBy.containsKey(broj)) return 'Zauzeto';
    final konobar = occupied[broj]?.konobar;
    if (konobar != null) return konobar;
    // While our order is still arriving the table isn't in stolovi_stanje yet,
    // so show our own name — the one the kasa will show once it lands, so
    // nothing changes then.
    if (pendingTransfer.contains(broj) || landed.contains(broj)) return myName;
    final cuser = unsentBy[broj] ?? sendingBy[broj];
    return cuser == null ? null : userNames[cuser];
  }

  bool isLocked(int broj) => lockedBy.containsKey(broj);
}
