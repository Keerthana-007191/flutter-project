import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 1) Paste your Supabase values here (Project Settings > API)
const supabaseUrl = 'https://ronrfyfyatlmgopvbepj.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJvbnJmeWZ5YXRsbWdvcHZiZXBqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEzODk3NDksImV4cCI6MjEwNjk2NTc0OX0.Yd8DBqFv1CVP6s5pijJ3WNFa2HhOGKidAJKiMlF6qkA';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const MyApp());
}

final db = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doctor Appointments',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [const DoctorsPage(), const MyAppointmentsPage()];
    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? 'Find a Doctor' : 'My Appointments'),
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.medical_services_outlined), label: 'Doctors'),
          NavigationDestination(
              icon: Icon(Icons.event_note_outlined), label: 'Appointments'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Doctors
class DoctorsPage extends StatelessWidget {
  const DoctorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: db.from('doctors').select().order('name'),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final doctors = snap.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: doctors.length,
          itemBuilder: (context, i) {
            final d = doctors[i];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(d['name']),
                subtitle: Text(
                    '${d['specialization']} • ${d['experience_years']} yrs\nFee: ₹${d['fee']}'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => BookingPage(doctor: d)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Booking
class BookingPage extends StatefulWidget {
  final Map<String, dynamic> doctor;
  const BookingPage({super.key, required this.doctor});
  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  String? _slot;
  Set<String> _booked = {};
  bool _loading = false;

  final List<String> _allSlots = [
    '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
    '14:00', '14:30', '15:00', '15:30', '16:00', '16:30',
  ];

  String get _dateStr => _date.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _loadBooked();
  }

  Future<void> _loadBooked() async {
    final rows = await db
        .from('appointments')
        .select('slot_time')
        .eq('doctor_id', widget.doctor['id'])
        .eq('appointment_date', _dateStr)
        .eq('status', 'Booked');
    setState(() {
      _booked = rows.map<String>((r) => r['slot_time'] as String).toSet();
      if (_booked.contains(_slot)) _slot = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        _slot = null;
      });
      _loadBooked();
    }
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _book() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || phone.length < 10 || _slot == null) {
      _msg('Enter name, a valid phone number and pick a slot');
      return;
    }
    setState(() => _loading = true);
    try {
      final patient = await db
          .from('patients')
          .upsert({'name': name, 'phone': phone}, onConflict: 'phone')
          .select()
          .single();
      await db.from('appointments').insert({
        'doctor_id': widget.doctor['id'],
        'patient_id': patient['id'],
        'appointment_date': _dateStr,
        'slot_time': _slot,
      });
      if (!mounted) return;
      _msg('Appointment booked!');
      Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        _msg('Sorry, that slot was just taken. Pick another.');
        _loadBooked();
      } else {
        _msg('Error: ${e.message}');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doctor;
    return Scaffold(
      appBar: AppBar(title: Text(d['name'])),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${d['specialization']} • Fee ₹${d['fee']}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today),
            label: Text('Date: $_dateStr'),
          ),
          const SizedBox(height: 16),
          const Text('Select a slot'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allSlots.map((s) {
              final taken = _booked.contains(s);
              return ChoiceChip(
                label: Text(s),
                selected: _slot == s,
                onSelected: taken ? null : (_) => setState(() => _slot = s),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Patient name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Phone number', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _book,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Confirm Booking'),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------- My appointments
class MyAppointmentsPage extends StatefulWidget {
  const MyAppointmentsPage({super.key});
  @override
  State<MyAppointmentsPage> createState() => _MyAppointmentsPageState();
}

class _MyAppointmentsPageState extends State<MyAppointmentsPage> {
  final _phone = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _searched = false;

  Future<void> _search() async {
    final rows = await db
        .from('appointments')
        .select(
            'id, appointment_date, slot_time, status, doctors(name, specialization), patients!inner(phone)')
        .eq('patients.phone', _phone.text.trim())
        .order('appointment_date', ascending: false);
    setState(() {
      _rows = rows;
      _searched = true;
    });
  }

  Future<void> _cancel(int id) async {
    await db.from('appointments').update({'status': 'Cancelled'}).eq('id', id);
    _search();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Enter your phone number',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _search, child: const Text('Search')),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: _rows.isEmpty
                ? Center(
                    child: Text(_searched
                        ? 'No appointments found'
                        : 'Search with your phone number'))
                : ListView.builder(
                    itemCount: _rows.length,
                    itemBuilder: (context, i) {
                      final a = _rows[i];
                      final booked = a['status'] == 'Booked';
                      return Card(
                        child: ListTile(
                          title: Text(a['doctors']['name']),
                          subtitle: Text(
                              '${a['doctors']['specialization']}\n${a['appointment_date']} at ${a['slot_time']} • ${a['status']}'),
                          isThreeLine: true,
                          trailing: booked
                              ? TextButton(
                                  onPressed: () => _cancel(a['id']),
                                  child: const Text('Cancel'))
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
