import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'config.dart';
import 'firestore_service.dart';
import 'functions_service.dart';
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
    final pages = [const DashboardPage(), const PlansPage(), const PaymentsPage(), const BookingsPage(), const ContentPage(), const SlotsPage(), const SmtpPage()];
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
          BottomNavigationBarItem(icon: Icon(Icons.payment), label: 'Payments'),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Bookings'),
          BottomNavigationBarItem(icon: Icon(Icons.edit), label: 'Content'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Slots'),
          BottomNavigationBarItem(icon: Icon(Icons.email), label: 'SMTP'),
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

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});
  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

/// Razorpay setup, exactly as the owner confirmed it:
/// - The KEY ID is entered here and saved into the `content/settings`
///   Firestore document. The booking app reads it from Firebase at runtime.
///   The key ID is a publishable checkout identifier, not a secret.
/// - The SECRET is never entered here, never saved in Firestore, never in
///   the repo or either app. It lives only as a Cloud Functions secret,
///   set by the owner with:
///     firebase functions:secrets:set RAZORPAY_SECRET
///   then `firebase deploy --only functions`.
/// Payment statuses flow: pending_payment -> paid / failed. `failed` is set
/// only by server signature verification; a dismissed checkout stays
/// pending_payment so the booker can retry. The owner can also confirm or
/// fail a payment manually here.
class _PaymentsPageState extends State<PaymentsPage> {
  final _key = TextEditingController();
  bool _keyLoaded = false;
  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Razorpay setup', style: TextStyle(fontWeight: FontWeight.bold)),
      StreamBuilder<AppSettings>(
        stream: FirestoreService.settingsStream(),
        builder: (c, s) {
          if (!_keyLoaded) {
            _key.text = s.data?.razorpayKeyId ?? '';
            _keyLoaded = true;
          }
          final set = s.data?.razorpayKeyId != null && s.data!.razorpayKeyId!.isNotEmpty;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Key ID status: ${set ? 'SET (booking app reads it from Firebase)' : 'NOT SET — payments stay pending until you set it'}'),
                const SizedBox(height: 8),
                TextField(controller: _key, decoration: const InputDecoration(labelText: 'Razorpay Key ID (starts with rzp_)', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    final v = _key.text.trim();
                    if (v.isEmpty || !v.startsWith('rzp_')) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a Razorpay Key ID starting with rzp_.')));
                      return;
                    }
                    await FirestoreService.saveSettings({'razorpayKeyId': v});
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Key ID saved to Firebase. The booking app picks it up at runtime, no rebuild needed.')));
                  },
                  child: const Text('Save Key ID to Firebase'),
                ),
                const SizedBox(height: 8),
                const Text('Secret: NEVER type it here. Set it once with `firebase functions:secrets:set RAZORPAY_SECRET` and deploy functions. The secret is used server-side only, for order creation and signature verification.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
          );
        },
      ),
      const SizedBox(height: 16),
      const Text('Payments by booking', style: TextStyle(fontWeight: FontWeight.bold)),
      StreamBuilder<List<Booking>>(
        stream: FirestoreService.bookingsStream(),
        builder: (c, s) {
          final bookings = s.data ?? [];
          if (bookings.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('No bookings yet.'));
          return Column(
            children: bookings.map((b) => Card(
              child: ListTile(
                title: Text('${b.name} — total ${b.totalPrice == null ? 'TBD' : b.totalPrice.toString()}'),
                subtitle: Text('Payment: ${b.paymentStatus}${b.razorpayPaymentId != null ? ' • pay id ${b.razorpayPaymentId}' : ''}${b.paymentVerification != null ? ' • ${b.paymentVerification}' : ''}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => FirestoreService.setBookingPaymentStatus(b.id, v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'paid', child: Text('Mark paid')),
                    PopupMenuItem(value: 'failed', child: Text('Mark failed')),
                    PopupMenuItem(value: 'pending_payment', child: Text('Back to pending')),
                  ],
                ),
              ),
            )).toList(),
          );
        },
      ),
    ]);
  }
}

class SmtpPage extends StatefulWidget {
  const SmtpPage({super.key});
  @override
  State<SmtpPage> createState() => _SmtpPageState();
}

/// SMTP configuration inside the admin app.
/// - Host, port, user, sender, owner email and test recipient are saved to
///   the `content/smtp` Firestore document (non-secret fields only).
/// - The SMTP account is sunmughan@gmail.com. The password field below is
///   used ONLY for the test send tapped right after typing it: it is sent
///   to the test-mail function for that one send and is never stored
///   anywhere (not in Firestore, not in the repo, not in the app).
/// - Booking notification mail does NOT use the typed password: it uses the
///   SMTP_PASS Cloud Functions secret, set by the owner with:
///     firebase functions:secrets:set SMTP_PASS
///   then `firebase deploy --only functions`.
/// - Test mail goes ONLY to the test recipient (default sunmughan@gmail.com).
///   Booking mail goes ONLY to the owner email, never to the test recipient.
class _SmtpPageState extends State<SmtpPage> {
  final _host = TextEditingController(), _port = TextEditingController(), _user = TextEditingController(), _from = TextEditingController(), _owner = TextEditingController(), _testTo = TextEditingController(), _pass = TextEditingController();
  bool _loaded = false;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SmtpConfig?>(
      stream: FirestoreService.smtpStream(),
      builder: (c, s) {
        if (!_loaded) {
          final cfg = s.data;
          _host.text = cfg?.host ?? '';
          _port.text = cfg?.port?.toString() ?? '587';
          _user.text = cfg?.user ?? 'sunmughan@gmail.com';
          _from.text = cfg?.from ?? 'sunmughan@gmail.com';
          _owner.text = cfg?.ownerEmail ?? '';
          _testTo.text = cfg?.testRecipient ?? 'sunmughan@gmail.com';
          _loaded = true;
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('SMTP configuration (account: sunmughan@gmail.com)', style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(controller: _host, decoration: const InputDecoration(labelText: 'SMTP host (e.g. smtp.gmail.com)')),
          TextField(controller: _port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port (587)')),
          TextField(controller: _user, decoration: const InputDecoration(labelText: 'SMTP user')),
          TextField(controller: _from, decoration: const InputDecoration(labelText: 'Sender address (from)')),
          TextField(controller: _owner, decoration: const InputDecoration(labelText: 'Owner email (booking notifications go here)')),
          TextField(controller: _testTo, decoration: const InputDecoration(labelText: 'Test recipient (test mail only)')),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              await FirestoreService.saveSmtpConfig({
                'host': _host.text.trim(),
                'port': int.tryParse(_port.text) ?? 587,
                'user': _user.text.trim(),
                'from': _from.text.trim(),
                'ownerEmail': _owner.text.trim(),
                'testRecipient': _testTo.text.trim(),
              });
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SMTP settings saved (non-secret fields only). Password is never saved.')));
            },
            child: const Text('Save SMTP settings'),
          ),
          const SizedBox(height: 16),
          const Text('SMTP password — test send only, never stored', style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'SMTP password / app password (not saved anywhere)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              try {
                final r = _pass.text.isEmpty
                    ? await FunctionsService.sendTestMail()
                    : await FunctionsService.sendTestMail({
                        'host': _host.text.trim(),
                        'port': int.tryParse(_port.text) ?? 587,
                        'user': _user.text.trim(),
                        'pass': _pass.text,
                        'from': _from.text.trim(),
                        'to': _testTo.text.trim(),
                      });
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Test mail result: ${r['sent'] == true ? 'sent to ${r['to']}' : r['status'] ?? r}')));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Test mail failed: $e')));
              }
            },
            child: const Text('Send test mail'),
          ),
          const SizedBox(height: 8),
          const Text('Booking mail uses the SMTP_PASS function secret, not the password typed above. Set it with `firebase functions:secrets:set SMTP_PASS` and deploy functions. Without it, booking mail is skipped and logged, never faked as sent.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]);
      },
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
                    TextButton(onPressed: () { FirestoreService.setBookingPaymentStatus(b.id, 'paid'); Navigator.pop(context); }, child: const Text('Mark paid')),
                    TextButton(onPressed: () { FirestoreService.setBookingPaymentStatus(b.id, 'failed'); Navigator.pop(context); }, child: const Text('Mark failed')),
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
  final _manualFollowers = TextEditingController();
  bool _loaded = false;
  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Real-time stats (Himanshu @_kya_bro_)', style: TextStyle(fontWeight: FontWeight.bold)),
      StreamBuilder<CreatorStats?>(
        stream: FirestoreService.statsStream(),
        builder: (c, s) {
          final st = s.data;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st == null || st.isEmpty ? 'No stats stored yet.' : 'Followers: ${st.followersCount ?? '—'} • Posts: ${st.mediaCount ?? '—'} • Source: ${st.source ?? '—'}${st.updatedAtIso != null ? ' • Updated: ${st.updatedAtIso}' : ''}'),
                if (st?.lastError != null) Text('Last refresh note: ${st!.lastError}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        try {
                          final r = await FunctionsService.refreshCreatorStats();
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Stats refresh: ${r['status'] ?? r}')));
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Stats refresh failed: $e')));
                        }
                      },
                      child: const Text('Refresh from Instagram'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _manualFollowers, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Manual followers', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final v = int.tryParse(_manualFollowers.text);
                      if (v == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a follower count first.')));
                        return;
                      }
                      await FirestoreService.saveStats({'followersCount': v, 'source': 'manual', 'updatedAt': DateTime.now().toIso8601String(), 'lastError': null});
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manual followers saved and marked as owner-set.')));
                    },
                    child: const Text('Save manual'),
                  ),
                ]),
                const Text('Live fetch needs an Instagram access token secret (INSTAGRAM_ACCESS_TOKEN) on the functions. Without it the refresh reports "needs token" and writes nothing — numbers are never guessed. Manual entries are always labelled as owner-set in the public app.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
          );
        },
      ),
      const SizedBox(height: 16),
      const Text('Profile', style: TextStyle(fontWeight: FontWeight.bold)),
      TextField(controller: _display, decoration: const InputDecoration(labelText: 'Display name')),
      TextField(controller: _creator, decoration: const InputDecoration(labelText: 'Creator name')),
      TextField(controller: _handle, decoration: const InputDecoration(labelText: 'Handle')),
      TextField(controller: _city, decoration: const InputDecoration(labelText: 'City')),
      TextField(controller: _style, decoration: const InputDecoration(labelText: 'Content style')),
      TextField(controller: _followers, decoration: const InputDecoration(labelText: 'Followers text')),
      TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone (public bio number)')),
      TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
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
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () async {
          if (_viralTitle.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a title first.')));
            return;
          }
          await FirestoreService.saveViralPick({'title': _viralTitle.text.trim(), 'videoUrl': _viralUrl.text.trim(), 'note': _viralNote.text.trim(), 'source': 'manual'});
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to the viral videos list shown in the public app.')));
        },
        child: const Text('Add to viral videos list'),
      ),
      const SizedBox(height: 8),
      StreamBuilder<List<ViralPick>>(
        stream: FirestoreService.viralPicksStream(),
        builder: (c, s) {
          final picks = s.data ?? [];
          if (picks.isEmpty) return const Text('No viral videos in the list yet. Newest first; the public app shows the top 3.', style: TextStyle(fontSize: 12, color: Colors.grey));
          return Column(
            children: picks.map((v) => ListTile(
              title: Text(v.title ?? 'Untitled video'),
              subtitle: v.note == null || v.note!.isEmpty ? null : Text(v.note!),
              trailing: v.id == null ? null : IconButton(icon: const Icon(Icons.delete), onPressed: () => FirestoreService.deleteViralPick(v.id!)),
            )).toList(),
          );
        },
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
