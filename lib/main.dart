import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'device_calendar_service.dart';
import 'firestore_service.dart';
import 'models.dart';
import 'payment_service.dart';
import 'urgency.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.firebaseConfigured) {
    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseMessagingSenderId,
          projectId: AppConfig.firebaseProjectId,
          storageBucket: AppConfig.firebaseStorageBucket,
        ),
      );
      FirestoreService.available = true;
    } catch (_) {
      FirestoreService.available = false;
    }
  }
  runApp(const KyaBroApp());
}

const _daySlots = ['09:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:00', '16:00', '17:00', '18:00'];

class KyaBroApp extends StatelessWidget {
  const KyaBroApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Kya Bro Booking',
        theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
        home: const HomeShell(),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [const HomePage(), const BookingPage()];
    return Scaffold(
      appBar: AppBar(title: const Text('Kya Bro')),
      body: Column(children: [
        if (!FirestoreService.available)
          Container(
            width: double.infinity,
            color: Colors.amber.shade100,
            padding: const EdgeInsets.all(10),
            child: const Text(
              'Firebase is not connected yet. Content shows TBD / updated-by-owner states until the owner completes the Firebase console step (see README). No fake data is shown.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        Expanded(child: pages[_tab]),
      ]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Book'),
        ],
      ),
    );
  }
}

// ---------------- Home: profile + viral + engagement ----------------

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    if (!FirestoreService.available) {
      return ListView(children: const [
        ListTile(title: Text('Profile'), subtitle: Text('Updated by owner — connect Firebase to load content.')),
        ListTile(title: Text('Viral video'), subtitle: Text('Updated by owner.')),
        ListTile(title: Text('Engagement'), subtitle: Text('Updated by owner.')),
        ListTile(title: Text('Price'), subtitle: Text('TBD (set by owner)')),
      ]);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      StreamBuilder<Profile?>(
        stream: FirestoreService.profileStream(),
        builder: (c, s) {
          final p = s.data;
          if (p == null || p.isEmpty) {
            return const Card(child: ListTile(title: Text('Profile'), subtitle: Text('Updated by owner.')));
          }
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.displayName, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(p.creatorName, style: Theme.of(context).textTheme.titleMedium),
                Text(p.handle),
                Text(p.city),
                const SizedBox(height: 8),
                Text(p.contentStyle),
                if (p.followersText != null) Text(p.followersText!),
                if (p.bio != null) ...[const SizedBox(height: 8), Text(p.bio!)],
                const SizedBox(height: 12),
                Row(children: [
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BookingPage())),
                    child: const Text('Book Kya Bro'),
                  ),
                  const SizedBox(width: 8),
                  if (p.phone != null)
                    OutlinedButton(
                      onPressed: () async {
                        final uri = Uri.parse('tel:${p.phone}');
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      },
                      child: const Text('Call'),
                    ),
                ]),
                if (p.phone != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Direct call: ${p.phone} (public bio number, to confirm)'),
                  ),
                if (p.email != null) Text('Email: ${p.email}'),
              ]),
            ),
          );
        },
      ),
      const SizedBox(height: 12),
      StreamBuilder<ViralPick?>(
        stream: FirestoreService.viralStream(),
        builder: (c, s) {
          final v = s.data;
          if (v == null || v.isEmpty) {
            return const Card(child: ListTile(title: Text('Recent viral video'), subtitle: Text('Viral pick updated by owner.')));
          }
          return Card(
            child: ListTile(
              title: Text(v.title!),
              subtitle: v.note == null ? null : Text(v.note!),
              trailing: v.videoUrl == null ? null : const Icon(Icons.play_circle),
              onTap: v.videoUrl == null
                  ? null
                  : () async {
                      final uri = Uri.parse(v.videoUrl!);
                      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
            ),
          );
        },
      ),
      const SizedBox(height: 12),
      StreamBuilder<Engagement?>(
        stream: FirestoreService.engagementStream(),
        builder: (c, s) {
          final e = s.data;
          if (e == null || e.isEmpty) {
            return const Card(child: ListTile(title: Text('Engagement'), subtitle: Text('This week and this month numbers updated by owner.')));
          }
          Widget row(String label, int? views, int? likes, int? comments, int? shares) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('$label: views ${views ?? '—'}  •  likes ${likes ?? '—'}  •  comments ${comments ?? '—'}  •  shares ${shares ?? '—'}'),
              );
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Engagement', style: TextStyle(fontWeight: FontWeight.bold)),
                row('This week', e.weekViews, e.weekLikes, e.weekComments, e.weekShares),
                row('This month', e.monthViews, e.monthLikes, e.monthComments, e.monthShares),
              ]),
            ),
          );
        },
      ),
    ]);
  }
}

// ---------------- Booking ----------------

class BookingPage extends StatefulWidget {
  const BookingPage({super.key});
  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  String _type = 'Video';
  int _storyCount = 1;
  int _duration = 30; // seconds: 30, 45 or 60 ONLY
  String? _package; // Weekly | Monthly | null
  final _name = TextEditingController();
  final _purpose = TextEditingController();
  DateTime _slotDay = DateTime.now().add(const Duration(days: 1));
  String? _slotTime;
  DateTime? _deliveryDue;
  bool _submitting = false;

  DateTime _slotDateTime() {
    final t = (_slotTime ?? '09:00').split(':');
    return DateTime(_slotDay.year, _slotDay.month, _slotDay.day, int.parse(t[0]), int.parse(t[1]));
  }

  double? _basePrice(List<Plan> plans) {
    Plan? byKind(String kind) {
      for (final p in plans) {
        if (p.kind == kind) return p;
      }
      return null;
    }
    if (_package == 'Weekly') return byKind('weekly')?.basePrice;
    if (_package == 'Monthly') return byKind('monthly')?.basePrice;
    if (_type == 'Video') {
      for (final p in plans) {
        if (p.kind == 'video' && p.durationSeconds == _duration) return p.basePrice;
      }
    }
    if (_type == 'Story') {
      for (final p in plans) {
        if (p.kind == 'storyPack' && p.storyCount == _storyCount) return p.basePrice;
      }
    }
    return null;
  }

  Future<void> _submit(List<Plan> plans, double nextDayMultiplier) async {
    if (!FirestoreService.available) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Firebase is not connected yet. Complete the Firebase console step in the README, then book again.')));
      return;
    }
    if (_name.text.trim().isEmpty || _purpose.text.trim().isEmpty || _slotTime == null || _deliveryDue == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill name, business/purpose, a slot and a delivery time.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final orderedAt = DateTime.now();
      final urgency = calculateUrgency(orderedAt: orderedAt, deliveryDue: _deliveryDue!, nextDayMultiplier: nextDayMultiplier);
      final base = _basePrice(plans);
      final total = urgencyTotal(basePrice: base, multiplier: urgency.multiplier);
      final slotId = Slot.docIdFor(_slotDay, _slotTime!);
      final slotStart = _slotDateTime();
      final bookingData = <String, dynamic>{
        'name': _name.text.trim(),
        'purpose': _purpose.text.trim(),
        'type': _type,
        'storyCount': _type == 'Story' ? _storyCount : null,
        'durationSeconds': _type == 'Video' ? _duration : null,
        'packageKind': _package,
        'slotDate': '${_slotDay.year}-${_slotDay.month.toString().padLeft(2, '0')}-${_slotDay.day.toString().padLeft(2, '0')}',
        'slotStart': _slotTime,
        'slotEnd': 'TBD',
        'deliveryDue': _deliveryDue!.toIso8601String(),
        'urgencyTier': urgency.tierName,
        'multiplier': urgency.multiplier,
        'basePrice': base,
        'totalPrice': total,
        'paymentStatus': 'pending_payment',
      };
      final id = await FirestoreService.bookSlotTransaction(
        bookingData: bookingData,
        slotId: slotId,
        slotData: {'date': bookingData['slotDate'], 'startTime': _slotTime, 'endTime': 'TBD', 'status': 'booked'},
      );
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConfirmationPage(
          bookingId: id,
          name: _name.text.trim(),
          type: _type,
          storyCount: _type == 'Story' ? _storyCount : null,
          durationSeconds: _type == 'Video' ? _duration : null,
          packageKind: _package,
          slotStart: slotStart,
          deliveryDue: _deliveryDue!,
          urgency: urgency,
          basePrice: base,
          totalPrice: total,
        ),
      ));
    } on StateError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!FirestoreService.available) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Booking needs Firebase. Complete the Firebase console step in the README, then this form books a real slot.')));
    }
    return StreamBuilder<List<Plan>>(
      stream: FirestoreService.plansStream(),
      builder: (c, planSnap) {
        final plans = planSnap.data ?? [];
        return StreamBuilder<AppSettings>(
          stream: FirestoreService.settingsStream(),
          builder: (c, setSnap) {
            final mult = setSnap.data?.nextDayMultiplier ?? 1.25;
            final base = _basePrice(plans);
            final urgency = _deliveryDue == null
                ? null
                : calculateUrgency(orderedAt: DateTime.now(), deliveryDue: _deliveryDue!, nextDayMultiplier: mult);
            final total = urgency == null ? null : urgencyTotal(basePrice: base, multiplier: urgency.multiplier);
            return StreamBuilder<Set<String>>(
              stream: FirestoreService.blockedDaysStream(),
              builder: (c, blockSnap) {
                final blocked = blockSnap.data ?? {};
                return StreamBuilder<List<Slot>>(
                  stream: FirestoreService.slotsForDayStream(_slotDay),
                  builder: (c, slotSnap) {
                    final byTime = {for (final s in slotSnap.data ?? []) s.startTime: s};
                    final dayKey = '${_slotDay.year}-${_slotDay.month.toString().padLeft(2, '0')}-${_slotDay.day.toString().padLeft(2, '0')}';
                    final dayBlocked = blocked.contains(dayKey);
                    return ListView(padding: const EdgeInsets.all(16), children: [
                      const Text('Booking type', style: TextStyle(fontWeight: FontWeight.bold)),
                      Wrap(spacing: 8, children: ['Story', 'Video', 'Post', 'Carousel'].map((t) => ChoiceChip(label: Text(t), selected: _type == t, onSelected: (_) => setState(() => _type = t))).toList()),
                      if (_type == 'Story') ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          const Text('How many stories: '),
                          IconButton(icon: const Icon(Icons.remove), onPressed: _storyCount > 1 ? () => setState(() => _storyCount--) : null),
                          Text('$_storyCount'),
                          IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => _storyCount++)),
                        ]),
                      ],
                      if (_type == 'Video') ...[
                        const SizedBox(height: 12),
                        const Text('Video duration', style: TextStyle(fontWeight: FontWeight.bold)),
                        Wrap(spacing: 8, children: [30, 45, 60].map((d) => ChoiceChip(label: Text('${d}s'), selected: _duration == d, onSelected: (_) => setState(() => _duration = d))).toList()),
                      ],
                      const SizedBox(height: 12),
                      const Text('Package', style: TextStyle(fontWeight: FontWeight.bold)),
                      Wrap(spacing: 8, children: [
                        ChoiceChip(label: const Text('No package'), selected: _package == null, onSelected: (_) => setState(() => _package = null)),
                        ChoiceChip(label: const Text('Weekly'), selected: _package == 'Weekly', onSelected: (_) => setState(() => _package = 'Weekly')),
                        ChoiceChip(label: const Text('Monthly'), selected: _package == 'Monthly', onSelected: (_) => setState(() => _package = 'Monthly')),
                      ]),
                      const SizedBox(height: 12),
                      TextField(controller: _name, decoration: const InputDecoration(labelText: 'Your name', border: OutlineInputBorder())),
                      const SizedBox(height: 12),
                      TextField(controller: _purpose, decoration: const InputDecoration(labelText: 'Business / purpose', border: OutlineInputBorder())),
                      const SizedBox(height: 16),
                      const Text('Pick a day and time (booked slots are greyed and cannot be selected)', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: Text('Day: $dayKey${dayBlocked ? ' — blocked by owner' : ''}')),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(context: context, initialDate: _slotDay, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)));
                            if (picked != null) setState(() { _slotDay = picked; _slotTime = null; });
                          },
                          child: const Text('Change day'),
                        ),
                      ]),
                      if (dayBlocked)
                        const Text('This day is blocked by the owner. Pick another day.', style: TextStyle(color: Colors.red))
                      else
                        Wrap(spacing: 8, runSpacing: 8, children: _daySlots.map((t) {
                          final slot = byTime[t];
                          final occupied = slot != null && !slot.bookable;
                          final selected = _slotTime == t;
                          return ChoiceChip(
                            label: Text(occupied ? '$t (booked)' : t),
                            selected: selected,
                            selectedColor: Colors.deepOrange.shade200,
                            disabledColor: Colors.grey.shade300,
                            onSelected: occupied ? null : (_) => setState(() => _slotTime = t),
                          );
                        }).toList()),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: Text(_deliveryDue == null ? 'Delivery needed by: not set' : 'Delivery needed by: ${_deliveryDue.toString()}')),
                        TextButton(
                          onPressed: () async {
                            final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 3)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)));
                            if (d == null) return;
                            final tod = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 18, minute: 0));
                            if (tod == null) return;
                            setState(() => _deliveryDue = DateTime(d.year, d.month, d.day, tod.hour, tod.minute));
                          },
                          child: const Text('Set delivery'),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Price breakdown', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('Base price: ${base == null ? 'TBD (set by owner)' : base.toStringAsFixed(0)}'),
                            if (urgency != null) ...[
                              Text('Urgency tier: ${urgency.tierName}'),
                              Text('Multiplier: ${urgency.multiplier}x'),
                              Text('Formula: ${urgency.formula}'),
                              Text('Total: ${total == null ? 'TBD until a base price is set' : total.toStringAsFixed(0)}'),
                            ] else
                              const Text('Set a delivery time to see the urgency tier.'),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _submitting || dayBlocked ? null : () => _submit(plans, mult),
                        child: Text(_submitting ? 'Booking…' : 'Confirm booking'),
                      ),
                      const SizedBox(height: 8),
                      const Text('Payment: if no Razorpay key is configured, the booking is saved as pending payment and the owner confirms it. No payment is faked.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ]);
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

// ---------------- Confirmation ----------------

class ConfirmationPage extends StatefulWidget {
  final String bookingId, name, type;
  final int? storyCount, durationSeconds;
  final String? packageKind;
  final DateTime slotStart, deliveryDue;
  final UrgencyResult urgency;
  final double? basePrice, totalPrice;
  const ConfirmationPage({
    super.key,
    required this.bookingId,
    required this.name,
    required this.type,
    this.storyCount,
    this.durationSeconds,
    this.packageKind,
    required this.slotStart,
    required this.deliveryDue,
    required this.urgency,
    this.basePrice,
    this.totalPrice,
  });
  @override
  State<ConfirmationPage> createState() => _ConfirmationPageState();
}

class _ConfirmationPageState extends State<ConfirmationPage> {
  String? _calendarNote;
  bool _paying = false;
  final PaymentService _payment = PaymentService();
  @override
  void initState() {
    super.initState();
    _payment.init();
  }

  @override
  void dispose() {
    _payment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payment = _payment;
    return Scaffold(
      appBar: AppBar(title: const Text('Booking summary')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Booking saved: ${widget.bookingId}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Name: ${widget.name}'),
        Text('Type: ${widget.type}${widget.storyCount != null ? ' x ${widget.storyCount}' : ''}${widget.durationSeconds != null ? ' (${widget.durationSeconds}s)' : ''}'),
        if (widget.packageKind != null) Text('Package: ${widget.packageKind}'),
        Text('Slot: ${widget.slotStart}'),
        Text('Delivery needed by: ${widget.deliveryDue}'),
        Text('Urgency: ${widget.urgency.tierName} (${widget.urgency.multiplier}x)'),
        Text('Formula: ${widget.urgency.formula}'),
        Text('Base price: ${widget.basePrice == null ? 'TBD (set by owner)' : widget.basePrice.toString()}'),
        Text('Total: ${widget.totalPrice == null ? 'TBD until a base price is set' : widget.totalPrice.toString()}'),
        const SizedBox(height: 8),
        const Text('Payment status: pending payment (no Razorpay key configured, or total TBD). The owner confirms the booking in the admin app.', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _paying
              ? null
              : () async {
                  if (widget.totalPrice == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Total is TBD until the owner sets a price. Payment opens once a price exists.')));
                    return;
                  }
                  setState(() => _paying = true);
                  payment.onSuccess = () {
                    FirebaseFirestore.instance.collection('bookings').doc(widget.bookingId).update({'paymentStatus': 'paid'});
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment successful.')));
                    setState(() => _paying = false);
                  };
                  payment.onFailure = (m) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment: $m')));
                    setState(() => _paying = false);
                  };
                  final opened = payment.openCheckout(amountInr: widget.totalPrice!, bookingId: widget.bookingId, name: widget.name);
                  if (!opened) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Razorpay key configured — booking stays pending payment.')));
                    setState(() => _paying = false);
                  }
                },
          child: const Text('Pay now (Razorpay)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            final ok = await DeviceCalendarService().addConfirmedBooking(
              title: 'Kya Bro booking — ${widget.type}',
              start: widget.slotStart,
              end: widget.slotStart.add(const Duration(hours: 1)),
              description: 'Booking ${widget.bookingId} for ${widget.name}. Delivery by ${widget.deliveryDue}.',
            );
            setState(() => _calendarNote = ok ? 'Added to your phone calendar.' : 'Could not add to calendar — check calendar permission and try again.');
          },
          child: const Text('Add to my phone calendar'),
        ),
        if (_calendarNote != null) Text(_calendarNote!),
        const SizedBox(height: 12),
        const Text('Email note: an email to Himanshu is sent by a server-side sender (see README). Until that backend step is done, this summary is shown here for manual sending. No email is claimed as sent from the app itself.', style: TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    );
  }
}
