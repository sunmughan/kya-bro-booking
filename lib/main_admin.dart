import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'config.dart';
import 'firestore_service.dart';
import 'models.dart';

/// ADMIN APP — second entry point of the same project.
/// Build it with: flutter build apk -t lib/main_admin.dart
/// Distribute the admin APK to the owner only. It writes the same Firestore
/// documents the public app reads, so changes appear with no code change.
/// Note: v1 has no Firebase Auth gate (see README "Security note"); add
/// Auth and tighten firestore.rules before any public distribution.
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
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Kya Bro Admin',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const AdminHome(),
      );
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    if (!FirestoreService.available) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kya Bro Admin')),
        body: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Firebase is not connected yet. Complete the Firebase console step in the README, then the admin app can manage content, plans, slots and bookings.'))),
      );
    }
    final pages = [const DashboardPage(), const PlansPage(), const BookingsPage(), const ContentPage(), const SlotsPage()];
    return Scaffold(
      appBar: AppBar(title: const Text('Kya Bro Admin')),
      body: pages[_tab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Plans'),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Bookings'),
          BottomNavigationBarItem(icon: Icon(Icons.edit), label: 'Content'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Slots'),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Booking>>(
      stream: FirestoreService.bookingsStream(),
      builder: (c, s) {
        final bookings = s.data ?? [];
        final pending = bookings.where((b) => b.status == 'new').length;
        final confirmed = bookings.where((b) => b.status == 'confirmed').length;
        final done = bookings.where((b) => b.status == 'done').length;
        final now = DateTime.now();
        final week = bookings.where((b) {
          final d = DateTime.tryParse(b.slotDate);
          return d != null && d.isAfter(now.subtract(const Duration(days: 7)));
        }).length;
        final month = bookings.where((b) {
          final d = DateTime.tryParse(b.slotDate);
          return d != null && d.isAfter(now.subtract(const Duration(days: 30)));
        }).length;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Week bookings: $week', style: Theme.of(context).textTheme.titleMedium),
          Text('Month bookings: $month', style: Theme.of(context).textTheme.titleMedium),
          Text('Pending (new): $pending'),
          Text('Confirmed: $confirmed'),
          Text('Done: $done'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              await FirestoreService.seedStarterContent();
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Starter profile + settings written. Engagement and prices stay empty until you fill them.')));
            },
            child: const Text('Load starter profile content'),
          ),
          const SizedBox(height: 8),
          const Text('Starter content is identity/contact only. Engagement numbers and prices are never seeded — fill them in Content / Plans so the public app never shows invented numbers.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]);
      },
    );
  }
}

class PlansPage extends StatefulWidget {
  const PlansPage({super.key});
  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  final _mult = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Plan>>(
      stream: FirestoreService.plansStream(),
      builder: (c, s) {
        final plans = s.data ?? [];
        return ListView(padding: const EdgeInsets.all(16), children: [
          StreamBuilder<AppSettings>(
            stream: FirestoreService.settingsStream(),
            builder: (c, ss) {
              if (_mult.text.isEmpty) _mult.text = (ss.data?.nextDayMultiplier ?? 1.25).toString();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Next-day urgency multiplier (owner sets 1.25 – 1.30, default 1.25)', style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(children: [
                      Expanded(child: TextField(controller: _mult, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder()))),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final v = double.tryParse(_mult.text);
                          if (v == null || v < 1.25 || v > 1.30) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a value between 1.25 and 1.30.')));
                            return;
                          }
                          await FirestoreService.saveSettings({'nextDayMultiplier': v});
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
                        },
                        child: const Text('Save'),
                      ),
                    ]),
                    const Text('12h = 2.0x and 24h = 1.5x are fixed. Normal = 1.0x.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ]),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          const Text('Plans & pricing (leave price empty = TBD in the public app)', style: TextStyle(fontWeight: FontWeight.bold)),
          ...plans.map((p) => _PlanEditor(plan: p)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _addPlanDialog(context),
            child: const Text('Add plan'),
          ),
          const SizedBox(height: 8),
          const Text('Video durations allowed: 30, 45, 60 seconds only. Kinds: weekly, monthly, storyPack, video.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]);
      },
    );
  }

  Future<void> _addPlanDialog(BuildContext context) async {
    final id = TextEditingController(), name = TextEditingController(), kind = TextEditingController(text: 'weekly'), price = TextEditingController(), dur = TextEditingController(), stories = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add plan'),
        content: SingleChildScrollView(
          child: Column(children: [
            TextField(controller: id, decoration: const InputDecoration(labelText: 'Plan id (e.g. weekly)')),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: kind, decoration: const InputDecoration(labelText: 'Kind: weekly/monthly/storyPack/video')),
            TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Base price (empty = TBD)')),
            TextField(controller: dur, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duration seconds (video only: 30/45/60)')),
            TextField(controller: stories, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Story count (storyPack only)')),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))],
      ),
    );
    if (ok != true || id.text.isEmpty) return;
    final d = int.tryParse(dur.text);
    if (kind.text == 'video' && d != null && d != 30 && d != 45 && d != 60) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video duration must be 30, 45 or 60 seconds.')));
      return;
    }
    await FirestoreService.savePlan(id.text.trim(), {
      'name': name.text.trim(),
      'kind': kind.text.trim(),
      'basePrice': double.tryParse(price.text),
      'durationSeconds': d,
      'storyCount': int.tryParse(stories.text),
    });
  }
}

class _PlanEditor extends StatelessWidget {
  final Plan plan;
  const _PlanEditor({required this.plan});
  @override
  Widget build(BuildContext context) {
    final price = TextEditingController(text: plan.basePrice?.toString() ?? '');
    return Card(
      child: ListTile(
        title: Text('${plan.name} (${plan.kind}${plan.durationSeconds != null ? ' ${plan.durationSeconds}s' : ''}${plan.storyCount != null ? ' x${plan.storyCount}' : ''})'),
        subtitle: Row(children: [
          Expanded(child: TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Base price (empty = TBD)'))),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              await FirestoreService.savePlan(plan.id, {'basePrice': double.tryParse(price.text)});
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Price saved.')));
            },
          ),
          IconButton(icon: const Icon(Icons.delete), onPressed: () => FirestoreService.deletePlan(plan.id)),
        ]),
      ),
    );
  }
}

class BookingsPage extends StatelessWidget {
  const BookingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Booking>>(
      stream: FirestoreService.bookingsStream(),
      builder: (c, s) {
        final bookings = s.data ?? [];
        if (bookings.isEmpty) return const Center(child: Text('No bookings yet.'));
        return ListView(
          children: bookings.map((b) => Card(
            child: ListTile(
              title: Text('${b.name} — ${b.type} (${b.status})'),
              subtitle: Text('${b.slotDate} ${b.slotStart} • ${b.purpose} • urgency ${b.urgencyTier ?? '—'} (${b.multiplier ?? '—'}x) • total ${b.totalPrice == null ? 'TBD' : b.totalPrice.toString()} • payment ${b.paymentStatus}'),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => FirestoreService.setBookingStatus(b.id, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'confirmed', child: Text('Confirm')),
                  PopupMenuItem(value: 'done', child: Text('Done')),
                  PopupMenuItem(value: 'new', child: Text('Back to New')),
                ],
              ),
              onTap: () => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text('Booking ${b.id}'),
                  content: Text('Name: ${b.name}\nPurpose: ${b.purpose}\nType: ${b.type}${b.storyCount != null ? ' x${b.storyCount}' : ''}${b.durationSeconds != null ? ' ${b.durationSeconds}s' : ''}\nPackage: ${b.packageKind ?? '—'}\nSlot: ${b.slotDate} ${b.slotStart}\nUrgency: ${b.urgencyTier} x${b.multiplier}\nBase: ${b.basePrice ?? 'TBD'} Total: ${b.totalPrice ?? 'TBD'}\nPayment: ${b.paymentStatus}\nStatus: ${b.status}'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                    FilledButton(onPressed: () { FirestoreService.setBookingStatus(b.id, 'confirmed'); Navigator.pop(context); }, child: const Text('Confirm')),
                    FilledButton(onPressed: () { FirestoreService.setBookingStatus(b.id, 'done'); Navigator.pop(context); }, child: const Text('Done')),
                  ],
                ),
              ),
            ),
          )).toList(),
        );
      },
    );
  }
}

class ContentPage extends StatefulWidget {
  const ContentPage({super.key});
  @override
  State<ContentPage> createState() => _ContentPageState();
}

class _ContentPageState extends State<ContentPage> {
  final _display = TextEditingController(), _creator = TextEditingController(), _handle = TextEditingController(), _city = TextEditingController(), _style = TextEditingController(), _followers = TextEditingController(), _phone = TextEditingController(), _email = TextEditingController(), _bio = TextEditingController();
  final _viralTitle = TextEditingController(), _viralUrl = TextEditingController(), _viralNote = TextEditingController();
  final _wViews = TextEditingController(), _wLikes = TextEditingController(), _wComments = TextEditingController(), _wShares = TextEditingController(), _mViews = TextEditingController(), _mLikes = TextEditingController(), _mComments = TextEditingController(), _mShares = TextEditingController();
  bool _loaded = false;
  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Profile', style: TextStyle(fontWeight: FontWeight.bold)),
      TextField(controller: _display, decoration: const InputDecoration(labelText: 'Display name')),
      TextField(controller: _creator, decoration: const InputDecoration(labelText: 'Creator name')),
      TextField(controller: _handle, decoration: const InputDecoration(labelText: 'Handle')),
      TextField(controller: _city, decoration: const InputDecoration(labelText: 'City')),
      TextField(controller: _style, decoration: const InputDecoration(labelText: 'Content style')),
      TextField(controller: _followers, decoration: const InputDecoration(labelText: 'Followers text')),
      TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone (public bio number)')),
      TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email (or "to confirm")')),
      TextField(controller: _bio, decoration: const InputDecoration(labelText: 'Bio')),
      FilledButton(
        onPressed: () async {
          await FirestoreService.saveProfile({'displayName': _display.text, 'creatorName': _creator.text, 'handle': _handle.text, 'city': _city.text, 'contentStyle': _style.text, 'followersText': _followers.text, 'phone': _phone.text, 'email': _email.text, 'bio': _bio.text});
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved.')));
        },
        child: const Text('Save profile'),
      ),
      const SizedBox(height: 16),
      const Text('Viral pick', style: TextStyle(fontWeight: FontWeight.bold)),
      TextField(controller: _viralTitle, decoration: const InputDecoration(labelText: 'Title (empty = updated-by-owner state)')),
      TextField(controller: _viralUrl, decoration: const InputDecoration(labelText: 'Video URL')),
      TextField(controller: _viralNote, decoration: const InputDecoration(labelText: 'Note')),
      FilledButton(
        onPressed: () async {
          await FirestoreService.saveViral({'title': _viralTitle.text, 'videoUrl': _viralUrl.text, 'note': _viralNote.text});
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Viral pick saved.')));
        },
        child: const Text('Save viral pick'),
      ),
      const SizedBox(height: 16),
      const Text('Engagement — week / month (empty = updated-by-owner state, never guessed)', style: TextStyle(fontWeight: FontWeight.bold)),
      Row(children: [Expanded(child: TextField(controller: _wViews, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Week views'))), const SizedBox(width: 8), Expanded(child: TextField(controller: _wLikes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Week likes')))]),
      Row(children: [Expanded(child: TextField(controller: _wComments, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Week comments'))), const SizedBox(width: 8), Expanded(child: TextField(controller: _wShares, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Week shares')))]),
      Row(children: [Expanded(child: TextField(controller: _mViews, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Month views'))), const SizedBox(width: 8), Expanded(child: TextField(controller: _mLikes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Month likes')))]),
      Row(children: [Expanded(child: TextField(controller: _mComments, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Month comments'))), const SizedBox(width: 8), Expanded(child: TextField(controller: _mShares, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Month shares')))]),
      FilledButton(
        onPressed: () async {
          int? p(TextEditingController t) => int.tryParse(t.text);
          await FirestoreService.saveEngagement({'weekViews': p(_wViews), 'weekLikes': p(_wLikes), 'weekComments': p(_wComments), 'weekShares': p(_wShares), 'monthViews': p(_mViews), 'monthLikes': p(_mLikes), 'monthComments': p(_mComments), 'monthShares': p(_mShares)});
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Engagement saved.')));
        },
        child: const Text('Save engagement'),
      ),
      if (!_loaded) ...[
        const SizedBox(height: 8),
        const Text('Tip: fill fields from scratch, or tap Load starter profile content on Dashboard first, then edit here.', style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    ]);
  }
}

class SlotsPage extends StatefulWidget {
  const SlotsPage({super.key});
  @override
  State<SlotsPage> createState() => _SlotsPageState();
}

class _SlotsPageState extends State<SlotsPage> {
  DateTime _day = DateTime.now();
  final _reason = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final dayKey = '${_day.year}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}';
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('Day: $dayKey')),
        TextButton(
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 90)));
            if (d != null) setState(() => _day = d);
          },
          child: const Text('Change day'),
        ),
      ]),
      Row(children: [
        Expanded(child: TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Block reason (optional)'))),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () async {
            await FirestoreService.blockDay(dayKey, _reason.text);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Day blocked — public app greys the whole day.')));
          },
          child: const Text('Block day'),
        ),
        TextButton(
          onPressed: () async {
            await FirestoreService.unblockDay(dayKey);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Day unblocked.')));
          },
          child: const Text('Unblock'),
        ),
      ]),
      const SizedBox(height: 12),
      const Text('Slots for this day (status free/booked/blocked; booking via the public app creates booked slots automatically)', style: TextStyle(fontSize: 13)),
      StreamBuilder<List<Slot>>(
        stream: FirestoreService.slotsForDayStream(_day),
        builder: (c, s) {
          final slots = s.data ?? [];
          if (slots.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('No slot documents yet for this day. Default day times (09:00–18:00) are bookable in the public app until booked or blocked.'));
          return Column(
            children: slots.map((slot) => ListTile(
              title: Text('${slot.startTime} — ${slot.status}'),
              subtitle: slot.blockReason == null ? null : Text(slot.blockReason!),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => FirestoreService.setSlot(slot.id, {'status': v}),
                itemBuilder: (_) => const [PopupMenuItem(value: 'free', child: Text('Free')), PopupMenuItem(value: 'blocked', child: Text('Blocked')), PopupMenuItem(value: 'booked', child: Text('Booked'))],
              ),
            )).toList(),
          );
        },
      ),
    ]);
  }
}
